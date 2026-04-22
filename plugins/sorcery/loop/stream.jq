# Filter for claude's stream-json output used by loop.sh / task-loop.sh.
# Renders a concise terminal view: text deltas, tool-use summaries, test
# results, and the final "Iteration Result" block. Paired with render.ts,
# which renders the markdown between the  /  sentinels.

if .type == "stream_event" and .event.delta.type? == "text_delta" then
  .event.delta.text
elif .type == "result" then
  #  and  are sentinels that render.ts swaps for markdown ANSI.
  "\n\n[1;4m Iteration Result [0m\n" + (.result // "") + "\n"
elif .type == "assistant" then
  (.message.content[] |
    if .type == "tool_use" then
      if .name == "TodoWrite" then
        ((.input.todos // []) as $t |
         ($t | map(select(.status == "completed")) | length) as $d |
         ($t | length) as $n |
         ($t | map(select(.status == "in_progress")) | .[0].content // null) as $a |
         if $a then "\n[33m📋 [" + ($d|tostring) + "/" + ($n|tostring) + "] [1m▶ " + $a + "[0m\n"
         else "\n[33m📋 [" + ($d|tostring) + "/" + ($n|tostring) + "][0m\n" end)
      elif .name == "ToolSearch" then empty
      elif .name == "Edit" or .name == "Write" then
        # Show just the tail of the file path (last two components) so long
        # absolute paths don't wrap on narrow terminals.
        ((.input.file_path // "") as $p |
         "\n[36m  ✏ " + ($p | split("/") | .[-2:] | join("/")) + "[0m\n")
      else
        "\n→ " + .name + " | " + (.input.description // .input.file_path // .input.pattern // ((.input.command // "")[:80]) // "") + "\n"
      end
    else empty end
  ) // empty
elif .type == "user" then
  (.message.content[] |
    select(.type == "tool_result") |
    # .content can be a string, an array of content blocks (e.g. ToolSearch
    # emits tool_reference blocks), or null. Coerce to a single string so
    # split() below (which only accepts strings) doesn't crash jq.
    ( if (.content | type) == "string" then .content
      elif (.content | type) == "array" then
        [.content[]? | select(.type? == "text") | .text // ""] | join("\n")
      else "" end
    ) | split("\n")[] |
    if test("^\\s*\\d+ fail") and (test("^\\s*0 fail") | not) then
      "\n[31m  🧪 " + gsub("^\\s+"; "") + "[0m\n"
    elif test("^Ran \\d+ tests") then
      "\n[32m  🧪 " + . + "[0m\n"
    else empty end
  ) // empty
else
  empty
end
