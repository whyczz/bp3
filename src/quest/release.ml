(* release — pure semver, remote URL, QUEST.md frontmatter, version-file,
   and "What changed" release-notes engine. Zero I/O, zero git subprocesses;
   I/O lives in Release_io. *)

type bump = Major | Minor | Patch | None_bump

type semver = { major : int; minor : int; patch : int }

type release_target = GitHub of string | Local_tag

type node_summary = {
  node_id : string;
  state : string;
  commit : string option;
  subject : string;
}

type quest_meta = {
  status : string option;
  bump : string option;
  title : string;
  tldr : string;
}

type release_notes = {
  tag : string;
  title : string;
  body : string;
}

let parse_bump = function
  | "major" -> Some Major
  | "minor" -> Some Minor
  | "patch" -> Some Patch
  | "none" -> Some None_bump
  | _ -> None

let bump_to_string = function
  | Major -> "major"
  | Minor -> "minor"
  | Patch -> "patch"
  | None_bump -> "none"

let is_ascii_digit c = c >= '0' && c <= '9'

let parse_strict_uint s =
  let n = String.length s in
  if n = 0 then None
  else if n > 1 && s.[0] = '0' then None
  else
    let rec ok i = i >= n || (is_ascii_digit s.[i] && ok (i + 1)) in
    if ok 0 then int_of_string_opt s else None

let parse_semver_str s =
  match String.split_on_char '.' (String.trim s) with
  | [ a; b; c ] ->
      (match parse_strict_uint a, parse_strict_uint b, parse_strict_uint c with
       | Some major, Some minor, Some patch -> Some { major; minor; patch }
       | _ -> None)
  | _ -> None

let parse_semver_tag tag =
  let t = String.trim tag in
  if String.length t >= 2 && t.[0] = 'v' && is_ascii_digit t.[1] then
    parse_semver_str (String.sub t 1 (String.length t - 1))
  else None

let format_semver v = Printf.sprintf "%d.%d.%d" v.major v.minor v.patch
let format_tag v = "v" ^ format_semver v

let compare_semver a b =
  let c1 = Int.compare a.major b.major in
  if c1 <> 0 then c1
  else
    let c2 = Int.compare a.minor b.minor in
    if c2 <> 0 then c2
    else Int.compare a.patch b.patch

let latest_semver_tag tags =
  List.fold_left
    (fun acc raw ->
      match parse_semver_tag raw with
      | None -> acc
      | Some v ->
          (match acc with
           | None -> Some v
           | Some cur -> if compare_semver v cur > 0 then Some v else acc))
    None tags

let next_semver prev = function
  | None_bump -> None
  | bump ->
      let base = Option.value prev ~default:{ major = 0; minor = 0; patch = 0 } in
      (match bump with
       | Major -> Some { major = base.major + 1; minor = 0; patch = 0 }
       | Minor -> Some { major = base.major; minor = base.minor + 1; patch = 0 }
       | Patch -> Some { major = base.major; minor = base.minor; patch = base.patch + 1 }
       | None_bump -> None)

(* ---------- GitHub remote detection ---------- *)

let valid_gh_segment s =
  let n = String.length s in
  if n = 0 || s = "." || s = ".." then false
  else
    let ok c =
      (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
      || (c >= '0' && c <= '9') || c = '-' || c = '_' || c = '.' in
    let rec loop i = i >= n || (ok s.[i] && loop (i + 1)) in
    loop 0

let strip_suffix ~suffix s =
  let plen = String.length suffix and slen = String.length s in
  if slen >= plen && String.sub s (slen - plen) plen = suffix then
    String.sub s 0 (slen - plen)
  else s

let parse_github_repo raw_url =
  let u = String.trim raw_url in
  let rest_opt =
    match Util.strip_prefix ~prefix:"git@github.com:" u with
    | Some r -> Some r
    | None ->
        (match Util.strip_prefix ~prefix:"ssh://git@github.com/" u with
         | Some r -> Some r
         | None ->
             (match Util.strip_prefix ~prefix:"https://github.com/" u with
              | Some r -> Some r
              | None -> Util.strip_prefix ~prefix:"http://github.com/" u)) in
  match rest_opt with
  | None -> None
  | Some path ->
      let path = strip_suffix ~suffix:"/" path in
      let path = strip_suffix ~suffix:".git" path in
      (match String.split_on_char '/' path with
       | [ owner; repo ] when valid_gh_segment owner && valid_gh_segment repo ->
           Some (owner ^ "/" ^ repo)
       | _ -> None)

let classify_remote = function
  | Some url ->
      (match parse_github_repo url with
       | Some slug -> GitHub slug
       | None -> Local_tag)
  | None -> Local_tag

(* ---------- QUEST.md parsing & status update ---------- *)

let parse_frontmatter_lines lines =
  match lines with
  | first :: rest when String.trim first = "---" ->
      let rec take acc = function
        | [] -> ([], [])
        | l :: tl when String.trim l = "---" -> (List.rev acc, tl)
        | l :: tl -> take (l :: acc) tl in
      take [] rest
  | _ -> ([], lines)

let fm_field fm key =
  let rec go = function
    | [] -> None
    | l :: rest ->
        (match String.index_opt l ':' with
         | Some i when String.trim (String.sub l 0 i) = key ->
             let v = String.trim (String.sub l (i + 1) (String.length l - i - 1)) in
             if v = "" then None else Some v
         | _ -> go rest) in
  go fm

let extract_tldr body_lines =
  let is_tldr_header t =
    t = "TL;DR" || t = "## TL;DR" || t = "TL;DR:"
    || (String.length t > 6 && String.sub t 0 6 = "TL;DR:") in
  let is_stop_line t =
    t = "ELI5" || t = "## ELI5"
    || (String.length t >= 2 && t.[0] = '#' && t.[1] = '#') in
  let rec find = function
    | [] -> ""
    | l :: rest ->
        let t = String.trim l in
        if is_tldr_header t then
          let inline =
            if String.length t > 6 && String.sub t 0 6 = "TL;DR:" then
              [ String.trim (String.sub t 6 (String.length t - 6)) ]
            else [] in
          let rec collect acc seen_nonempty = function
            | [] -> List.rev acc
            | ln :: tl ->
                let lt = String.trim ln in
                if lt = "" then
                  if seen_nonempty then List.rev acc else collect acc false tl
                else if is_stop_line lt then List.rev acc
                else collect (lt :: acc) true tl in
          let collected = collect (List.rev inline) (inline <> []) rest in
          String.concat " " (List.filter (fun s -> s <> "") collected)
        else find rest in
  find body_lines

let parse_quest_md text =
  let lines = String.split_on_char '\n' text in
  let fm, body = parse_frontmatter_lines lines in
  let title =
    let rec go = function
      | [] -> ""
      | l :: rest ->
          if String.length l >= 2 && l.[0] = '#' && l.[1] = ' ' then
            String.trim (String.sub l 2 (String.length l - 2))
          else go rest in
    go body in
  {
    status = fm_field fm "status";
    bump = fm_field fm "bump";
    title;
    tldr = extract_tldr body;
  }

let set_quest_status_landed text =
  let lines = String.split_on_char '\n' text in
  match lines with
  | first :: rest when String.trim first = "---" ->
      let rec rewrite_fm acc found = function
        | [] -> None
        | l :: tl when String.trim l = "---" ->
            let fm_done =
              if found then List.rev acc
              else List.rev ("status: landed" :: acc) in
            Some (first :: fm_done @ (l :: tl))
        | l :: tl ->
            (match String.index_opt l ':' with
             | Some i when String.trim (String.sub l 0 i) = "status" ->
                 rewrite_fm ("status: landed" :: acc) true tl
             | _ -> rewrite_fm (l :: acc) found tl) in
      (match rewrite_fm [] false rest with
       | Some updated -> String.concat "\n" updated
       | None -> text)
  | _ -> text

(* ---------- version file rewriting ---------- *)

let is_bp3_version_line l =
  let t = String.trim l in
  let prefix = "let bp3_version = \"" in
  let plen = String.length prefix and tlen = String.length t in
  tlen > plen && String.sub t 0 plen = prefix && t.[tlen - 1] = '"'

let sync_bp3_version ~new_version text =
  let lines = String.split_on_char '\n' text in
  let matches = ref 0 in
  let updated =
    List.map
      (fun l ->
        if is_bp3_version_line l then begin
          incr matches;
          Printf.sprintf "let bp3_version = \"%s\"" new_version
        end else l)
      lines in
  match !matches with
  | 1 -> Ok (String.concat "\n" updated)
  | 0 -> Error "src/quest/gitx.ml: let bp3_version = \"...\" line not found"
  | n -> Error (Printf.sprintf "src/quest/gitx.ml: expected 1 bp3_version line, found %d" n)

(* ---------- "What changed" renderers ---------- *)

let short_sha sha =
  if String.length sha >= 7 then String.sub sha 0 7 else sha

let render_what_changed ~quest ~tag ~prev_tag ~(meta : quest_meta) ~nodes ~commit_subjects =
  let title =
    if meta.title <> "" then Printf.sprintf "%s — %s" tag meta.title else tag in
  let buf = Buffer.create 256 in
  Printf.bprintf buf "# %s\n\n" title;
  if meta.tldr <> "" then Printf.bprintf buf "%s\n\n" meta.tldr;
  Buffer.add_string buf "## What changed\n";
  (match nodes with
   | _ :: _ ->
       List.iter
         (fun n ->
           let sha_part =
             match n.commit with
             | Some c when c <> "" -> Printf.sprintf " (%s)" (short_sha c)
             | _ -> "" in
           let desc = if String.trim n.subject <> "" then String.trim n.subject else n.state in
           Printf.bprintf buf "- `%s`: %s%s\n" n.node_id desc sha_part)
         nodes
   | [] ->
       (match commit_subjects with
        | _ :: _ ->
            List.iter (fun s -> Printf.bprintf buf "- %s\n" (String.trim s)) commit_subjects
        | [] -> Printf.bprintf buf "- Promoted quest `%s`\n" quest));
  Printf.bprintf buf "\nQuest: `docs/quests/%s/QUEST.md`\n" quest;
  Printf.bprintf buf "Previous tag: %s\n" (Option.value prev_tag ~default:"none");
  { tag; title; body = Buffer.contents buf }

let render_commit_what_changed ~sha ~subject ~body ~tag ~prev_tag ~commit_subjects =
  let subj = String.trim subject in
  let title = if subj <> "" then Printf.sprintf "%s — %s" tag subj else tag in
  let buf = Buffer.create 256 in
  Printf.bprintf buf "# %s\n\n" title;
  let body_trim = String.trim body in
  if body_trim <> "" then Printf.bprintf buf "%s\n\n" body_trim;
  Buffer.add_string buf "## What changed\n";
  (match commit_subjects with
   | _ :: _ ->
       List.iter (fun s -> Printf.bprintf buf "- %s\n" (String.trim s)) commit_subjects
   | [] ->
       let label = if subj <> "" then subj else "Release commit" in
       Printf.bprintf buf "- %s (%s)\n" label (short_sha sha));
  Printf.bprintf buf "\nCommit: `%s`\n" (short_sha sha);
  Printf.bprintf buf "Previous tag: %s\n" (Option.value prev_tag ~default:"none");
  { tag; title; body = Buffer.contents buf }
