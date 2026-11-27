(* names — single source of truth for CLI doors, verbs, edges, states,
   flags, and E_* error codes across src/quest/ (codebase-diet clean.2,
   promoting docs/icebox/2026-11-22-names-constants.md). *)

(* ---------- doors ---------- *)
let door_q = "q"
let door_g_legacy = "g"
let door_harness = "harness"
let door_worktree = "worktree"
let door_config = "config"
let door_init_repo = "init-repo"
let door_hooks = "hooks"
let door_icebox = "icebox"
let door_warden = "warden"
let door_release = "release"
let door_db = "db"
let door_repo = "repo"
let door_ticket = "ticket"

let all_doors =
  [ door_q; door_g_legacy; door_harness; door_worktree; door_config;
    door_init_repo; door_hooks; door_icebox; door_warden; door_release;
    door_db; door_repo; door_ticket ]

(* ---------- verbs ---------- *)
let verb_c = "c"
let verb_create = "create"
let verb_r = "r"
let verb_read = "read"
let verb_u = "u"
let verb_update = "update"
let verb_d = "d"
let verb_delete = "delete"
let verb_dep = "dep"
let verb_diagram = "diagram"
let verb_metrics = "metrics"
let verb_brief = "brief"
let verb_desk = "desk"
let verb_derive = "derive"
let verb_inspect = "inspect"
let verb_remove = "remove"
let verb_prepare = "prepare"
let verb_check = "check"
let verb_exit = "exit"
let verb_list = "list"
let verb_land = "land"
let verb_prune = "prune"

let all_verbs =
  [ verb_c; verb_create; verb_r; verb_read; verb_u; verb_update;
    verb_d; verb_delete; verb_dep; verb_diagram; verb_metrics;
    verb_brief; verb_desk; verb_derive; verb_inspect; verb_remove;
    verb_prepare; verb_check; verb_exit; verb_list; verb_land; verb_prune ]

(* ---------- edges ---------- *)
let edge_handoff = "handoff"
let edge_grade = "grade"
let edge_verify = "verify"
let edge_land = "land"
let edge_block = "block"
let edge_resume = "resume"

let all_edges =
  [ edge_handoff; edge_grade; edge_verify; edge_land; edge_block; edge_resume ]

(* ---------- states ---------- *)
let st_proposed = "proposed"
let st_todo = "todo"
let st_handed_off = "handed_off"
let st_approved = "approved"
let st_landed = "landed"
let st_blocked = "blocked"
let st_deleted = "deleted"

let all_states =
  [ st_proposed; st_todo; st_handed_off; st_approved; st_landed; st_blocked; st_deleted ]

(* ---------- flags ---------- *)
let flag_reason = "--reason"
let flag_commit = "--commit"
let flag_verdict = "--verdict"
let flag_verify_verdict = "--verify-verdict"
let flag_mechanical = "--mechanical"
let flag_target = "--target"
let flag_type = "--type"
let flag_depends_on = "--depends-on"
let flag_format = "--format"
let flag_desk = "--desk"
let flag_mode = "--mode"

(* ---------- error codes ---------- *)
let e_usage = "E_USAGE"
let e_not_found = "E_NOT_FOUND"
let e_exists = "E_EXISTS"
let e_illegal_edge = "E_ILLEGAL_EDGE"
let e_dirty_tree = "E_DIRTY_TREE"
let e_commit_mismatch = "E_COMMIT_MISMATCH"
let e_dependency = "E_DEPENDENCY"
let e_missing_ancestor = "E_MISSING_ANCESTOR"
let e_dep_cycle = "E_DEP_CYCLE"
let e_human_required = "E_HUMAN_REQUIRED"
let e_stale_world = "E_STALE_WORLD"
let e_version_ahead = "E_VERSION_AHEAD"
let e_identity = "E_IDENTITY"
let e_invalid_plan = "E_INVALID_PLAN"
let e_not_handed_off = "E_NOT_HANDED_OFF"
let e_branch_checked_out = "E_BRANCH_CHECKED_OUT"
let e_worktree = "E_WORKTREE"
let e_main_worktree = "E_MAIN_WORKTREE"
let e_install_failed = "E_INSTALL_FAILED"
let e_remote_rejected = "E_REMOTE_REJECTED"
let e_release_exists = "E_RELEASE_EXISTS"
let e_gh_failed = "E_GH_FAILED"
let e_already_promoted = "E_ALREADY_PROMOTED"
let e_not_ready = "E_NOT_READY"
let e_not_fast_forward = "E_NOT_FAST_FORWARD"
let e_bump_missing = "E_BUMP_MISSING"
let e_merge_conflict = "E_MERGE_CONFLICT"
let e_verify_failed = "E_VERIFY_FAILED"
let e_invalid_config = "E_INVALID_CONFIG"

(* ---------- warning codes ---------- *)
let w_no_repo_config = "W_NO_REPO_CONFIG"
let w_local_skills_legacy = "W_LOCAL_SKILLS_LEGACY"
