import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import { StringEnum } from "@mariozechner/pi-ai";
import { Text } from "@mariozechner/pi-tui";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

const DEFAULT_TRANSCRIPT_PATH = "/tmp/live-transcript.txt";

interface CopilotState {
	transcriptPath: string;
	lastReadLine: number;
	recording: boolean;
}

export default function (pi: ExtensionAPI) {
	let state: CopilotState = {
		transcriptPath: process.env.MEETING_TRANSCRIPT_PATH ?? DEFAULT_TRANSCRIPT_PATH,
		lastReadLine: 0,
		recording: false,
	};

	// Restore state from session
	pi.on("session_start", async (_event, ctx) => {
		for (const entry of ctx.sessionManager.getBranch()) {
			if (entry.type === "custom" && entry.customType === "meeting-copilot-state") {
				state = { ...state, ...(entry.data as Partial<CopilotState>) };
			}
		}
	});

	// Status widget
	function updateWidget(ctx: { ui: { setWidget: (id: string, lines: string[], options?: any) => void } }) {
		if (!state.recording) {
			ctx.ui.setWidget("meeting-copilot", []);
			return;
		}
		const lines = [`🎙️ Meeting copilot active — ${state.transcriptPath}`];
		try {
			const content = fs.readFileSync(state.transcriptPath, "utf8");
			const lineCount = content.split("\n").filter(Boolean).length;
			lines.push(`   ${lineCount} lines captured, ${state.lastReadLine} read`);
		} catch {
			lines.push("   Waiting for transcript file...");
		}
		ctx.ui.setWidget("meeting-copilot", lines, { placement: "bottom" });
	}

	pi.registerTool({
		name: "meeting_copilot",
		label: "Meeting Copilot",
		description:
			"Live meeting transcription tool. Start/stop tracking a transcript file, read new lines since last check, or get the full transcript for summarization.",
		promptSnippet: "Track and read live meeting transcripts for context and summarization",
		promptGuidelines: [
			"Use meeting_copilot with action 'start' when the user begins a meeting or asks to transcribe.",
			"Use 'read_new' to get incremental transcript updates without re-reading the whole file.",
			"Use 'read_all' or 'summarize' at the end of a meeting to produce notes.",
		],
		parameters: Type.Object({
			action: StringEnum(["start", "stop", "status", "read_new", "read_all"] as const, {
				description:
					"start: begin tracking transcript file. stop: stop tracking. status: show current state. read_new: read lines since last check. read_all: read entire transcript.",
			}),
			path: Type.Optional(
				Type.String({
					description: `Path to transcript file. Defaults to ${DEFAULT_TRANSCRIPT_PATH}`,
				}),
			),
		}),

		async execute(toolCallId, params, signal, onUpdate, ctx) {
			const transcriptPath = params.path ?? state.transcriptPath;

			switch (params.action) {
				case "start": {
					state.transcriptPath = transcriptPath;
					state.lastReadLine = 0;
					state.recording = true;
					pi.appendEntry("meeting-copilot-state", state);
					updateWidget(ctx);
					const exists = fs.existsSync(transcriptPath);
					return {
						content: [
							{
								type: "text",
								text: `Meeting copilot started. Tracking: ${transcriptPath}\nFile ${exists ? "exists" : "not yet created — will read when it appears"}.`,
							},
						],
						details: { transcriptPath, exists },
					};
				}

				case "stop": {
					state.recording = false;
					pi.appendEntry("meeting-copilot-state", state);
					updateWidget(ctx);
					return {
						content: [{ type: "text", text: `Meeting copilot stopped. Read ${state.lastReadLine} lines total.` }],
						details: { linesRead: state.lastReadLine },
					};
				}

				case "status": {
					let lineCount = 0;
					let fileExists = false;
					try {
						const content = fs.readFileSync(state.transcriptPath, "utf8");
						lineCount = content.split("\n").filter(Boolean).length;
						fileExists = true;
					} catch {}
					return {
						content: [
							{
								type: "text",
								text: `Recording: ${state.recording}\nFile: ${state.transcriptPath} (${fileExists ? `${lineCount} lines` : "not found"})\nLast read position: line ${state.lastReadLine}`,
							},
						],
						details: { recording: state.recording, lineCount, lastReadLine: state.lastReadLine, fileExists },
					};
				}

				case "read_new": {
					try {
						const content = fs.readFileSync(state.transcriptPath, "utf8");
						const allLines = content.split("\n");
						const newLines = allLines.slice(state.lastReadLine).filter(Boolean);
						state.lastReadLine = allLines.length;
						pi.appendEntry("meeting-copilot-state", state);
						updateWidget(ctx);

						if (newLines.length === 0) {
							return {
								content: [{ type: "text", text: "No new transcript lines since last read." }],
								details: { newLines: 0 },
							};
						}
						return {
							content: [{ type: "text", text: newLines.join("\n") }],
							details: { newLines: newLines.length, totalLines: allLines.length },
						};
					} catch (err: any) {
						return {
							content: [{ type: "text", text: `Transcript file not found: ${state.transcriptPath}` }],
							details: {},
							isError: true,
						};
					}
				}

				case "read_all": {
					try {
						const content = fs.readFileSync(state.transcriptPath, "utf8");
						const lines = content.split("\n");
						state.lastReadLine = lines.length;
						pi.appendEntry("meeting-copilot-state", state);
						updateWidget(ctx);
						return {
							content: [{ type: "text", text: content }],
							details: { totalLines: lines.filter(Boolean).length },
						};
					} catch (err: any) {
						return {
							content: [{ type: "text", text: `Transcript file not found: ${state.transcriptPath}` }],
							details: {},
							isError: true,
						};
					}
				}

				default:
					return {
						content: [{ type: "text", text: `Unknown action: ${params.action}` }],
						details: {},
						isError: true,
					};
			}
		},

		renderCall(args, theme) {
			const action = args.action ?? "?";
			const filePath = args.path ?? state.transcriptPath;
			const label =
				action === "start"
					? `▶ Start tracking ${filePath}`
					: action === "stop"
						? "⏹ Stop tracking"
						: action === "read_new"
							? "📖 Read new lines"
							: action === "read_all"
								? "📖 Read full transcript"
								: action === "status"
									? "ℹ Status"
									: action;
			return Text(label, { color: theme.colors.muted });
		},
	});

	// Command shortcuts
	pi.registerCommand("meeting", {
		description: "Meeting copilot — start, stop, status",
		handler: async (args, ctx) => {
			const sub = (args ?? "").trim();
			if (sub === "start") {
				pi.sendUserMessage("Start the meeting copilot and track the transcript.");
			} else if (sub === "stop") {
				pi.sendUserMessage("Stop the meeting copilot and summarize the transcript.");
			} else if (sub === "status") {
				pi.sendUserMessage("Check meeting copilot status.");
			} else {
				ctx.ui.notify("Usage: /meeting start | stop | status", "info");
			}
		},
	});
}
