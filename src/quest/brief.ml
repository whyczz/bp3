(* The grader's cold brief (induct-inline-as-default brief.1): rendered
   by bp3 from the bound commit and the ledger, never worded by the
   author. `render` is pure; `inputs` gathers what it needs as of a
   ledger stamp, so the verb and the scrape (brief.2) build the same
   text from the same facts. No text the author typed reaches it: the
   previous round shows the commit it judged, never its --reason
   (red-ink round 2), and the only caller input is a validated desk. *)

type inputs = {
  quest : string;
  node : string;
  cycle : int;
  commit : string;                    (* full sha, the bound commit *)
  node_md : string option;            (* NODE.md at commit *)
  grading : string option;            (* GRADING.md at commit *)
  docs : string list;                 (* CLAUDE.md, AGENTS.md, CONSTRAINTS.md present at commit *)
  prev : string option;               (* commit the last needs_fix judged *)
  others : (string * string) list;    (* (commit, node): other nodes' bound commits in prev..commit *)
}

let short c = if String.length c > 7 then String.sub c 0 7 else c

(* The body under a "## <heading>" line, up to the next "## " line; the
   heading itself and trailing blank lines are left out. *)
let section heading md =
  let is_h2 l = String.length l >= 3 && String.sub l 0 3 = "## " in
  let rec find = function
    | [] -> None
    | l :: rest when String.trim l = "## " ^ heading -> Some rest
    | _ :: rest -> find rest in
  let rec until_h2 = function l :: rest when not (is_h2 l) -> l :: until_h2 rest | _ -> [] in
  let rec drop_blank = function l :: rest when String.trim l = "" -> drop_blank rest | xs -> xs in
  Option.map (fun rest ->
      until_h2 rest |> drop_blank |> List.rev |> drop_blank |> List.rev |> String.concat "\n")
    (find (String.split_on_char '\n' md))

let preamble =
  "You are a fresh, independent grader. You did not write this commit. Judge it only \
   against its acceptance gates and the repo's rules, and return the verdict as data \
   in your final message."

let rules =
  String.concat "\n"
    [ "Rules:";
      "- Make no edits to tracked files, no commits, and no `bp3 q` calls.";
      "- Put experiments in a fresh `mktemp -d` directory. Before you finish, `git status --short` must print nothing.";
      "- A finding is a false claim, a broken gate, or a test that can't fail. Wording you would write differently is not a finding.";
      "- An edit to GRADING.md, CONSTRAINTS.md, or this node's Acceptance gates is an owner-class finding, unless the node's Output names the file." ]

let verdict_shape =
  String.concat "\n"
    [ "Final message, exactly this shape:";
      "";
      "VERDICT: ship | needs_fix";
      "MECHANICAL: yes | no";
      "GATE: <the gate's exit code and its last 3 lines>";
      "FINDINGS:";
      "1. [critical|major|minor] <claim> — <evidence>";
      "   FIX: <the exact change, for needs_fix>";
      "CHECKED: <one line each>";
      "NOT CHECKED: <what and why>" ]

let node_md_path q n = Store.node_dir q n ^ "/NODE.md"
let quest_md_path q = Store.quest_dir q ^ "/QUEST.md"

let desk_line desk commit = "Desk: " ^ desk ^ " (check that `git rev-parse HEAD` prints " ^ commit ^ ")"

let render ?desk i =
  let c7 = short i.commit in
  let gates = match i.node_md with
    | None -> "(no NODE.md at " ^ c7 ^ ": that is a finding)"
    | Some md -> (match section "Acceptance gates" md with
        | Some s when String.trim s <> "" -> s
        | _ -> "(NODE.md at " ^ c7 ^ " has no Acceptance gates section: that is a finding)") in
  let read_first =
    String.concat "\n"
      ([ "Read first:";
         "- " ^ node_md_path i.quest i.node ^ " and " ^ quest_md_path i.quest ]
       @ (if i.docs = [] then [] else [ "- " ^ String.concat ", " i.docs ])
       @ [ "- `git show " ^ c7 ^ "`" ]) in
  let previous = match i.prev with
    | None -> []
    | Some p ->
        let p7 = short p in
        [ "Previous round: " ^ p7 ^ " was graded needs_fix. Re-judge the gates in full; \
           the change since is `git diff " ^ p7 ^ ".." ^ c7 ^ "`.\n\
           Other nodes' commits in that range: "
          ^ (match i.others with
             | [] -> "none."
             | xs -> String.concat ", " (List.map (fun (c, n) -> short c ^ " (" ^ n ^ ")") xs) ^ ".") ] in
  let grading = match i.grading with
    | Some g -> "Repo grading rules (GRADING.md at " ^ c7 ^ "):\n\n" ^ String.trim g
    | None -> "No GRADING.md at " ^ c7 ^ ": run the repo's documented test gate and name it." in
  String.concat "\n\n"
    ([ "Grade " ^ i.node ^ " at " ^ c7 ^ " (full SHA " ^ i.commit ^ ") in quest " ^ i.quest
       ^ ", cycle " ^ string_of_int i.cycle ^ ".";
       preamble; rules ]
     @ (match desk with Some d -> [ desk_line d i.commit ] | None -> [])
     @ [ read_first; "Acceptance gates (NODE.md at " ^ c7 ^ "):\n\n" ^ gates ]
     @ previous
     @ [ grading; verdict_shape ])
  ^ "\n"

(* ---------- inputs: the ledgers and git, as of a stamp ---------- *)

let node_edges q n = match Store.fold_node q n with
  | Some (_, _, text) -> Metrics.edges_of_text text
  | None -> []

(* Ledger stamps share one format, so they compare as strings. *)
let by upto (e : Metrics.edge) = match upto with Some u -> e.e_ts <= u | None -> true

(* A needs_fix (or a verify fail) sends the node back to todo, or to
   blocked at the cap; the line carries the commit it judged. *)
let last_needs_fix edges =
  List.fold_left (fun acc (e : Metrics.edge) ->
      if (e.e_edge = "grade" || e.e_edge = "verify") && (e.e_to = "todo" || e.e_to = "blocked")
      then (match e.e_commit with Some c -> Some c | None -> acc) else acc) None edges

let rev_range a b =
  let out, code = Gitx.git_out [ "rev-list"; a ^ ".." ^ b ] in
  if code <> 0 then [] else List.filter (fun s -> s <> "") (String.split_on_char '\n' out)

let inputs ~quest ~node ~cycle ~commit ~upto =
  let mine = List.filter (by upto) (node_edges quest node) in
  let prev = last_needs_fix mine in
  let others = match prev with
    | None -> []
    | Some p ->
        let range = rev_range p commit in
        List.concat_map (fun n ->
            if n = node then []
            else
              List.filter_map (fun (e : Metrics.edge) ->
                  match e.e_commit with
                  | Some c when e.e_edge = "handoff" && by upto e && List.mem c range -> Some (c, n)
                  | _ -> None) (node_edges quest n))
          (Store.list_nodes quest)
        |> List.sort_uniq compare in
  let show path = Gitx.git_show commit path in
  { quest; node; cycle; commit;
    node_md = show (node_md_path quest node);
    grading = show "GRADING.md";
    docs = List.filter (fun d -> show d <> None) [ "CLAUDE.md"; "AGENTS.md"; "CONSTRAINTS.md" ];
    prev; others }
