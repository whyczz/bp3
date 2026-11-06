open Packet
open OUnit2

let bound payload = Workspace.bind_session ~session:(Some "bp3-test") payload
let object_with name = obj [ ("session_name", str name); ("root", str "/tmp") ]

let rejects f =
  match f () with
  | _ -> assert_failure "expected refusal"
  | exception Packet.Error _ -> ()

let () =
  run_test_tt_main
    ("workspace"
    >::: [
           ( "outside workspace retains explicit session" >:: fun _ ->
             let p = object_with "external" in
             assert_equal p (Workspace.bind_session ~session:None p) );
           ( "missing session inherits binding" >:: fun _ ->
             assert_equal (str "bp3-test") (get (bound (obj [])) "session_name")
           );
           ( "null session inherits binding" >:: fun _ ->
             assert_equal (str "bp3-test")
               (get (bound (obj [ ("session_name", `Null) ])) "session_name") );
           ( "matching binding preserves other fields" >:: fun _ ->
             assert_equal (object_with "bp3-test")
               (bound (object_with "bp3-test")) );
           ( "cross-session launch refused" >:: fun _ ->
             rejects (fun () -> bound (object_with "another")) );
           ( "invalid environment ID refused" >:: fun _ ->
             rejects (fun () ->
                 Workspace.bind_session ~session:(Some "bad/name") (obj [])) );
           ( "malformed payload refused" >:: fun _ ->
             rejects (fun () -> bound (`List [])) );
           ( "single Worker tab in bound session without stealing focus"
           >:: fun _ ->
             assert_equal
               [
                 "zellij";
                 "--session";
                 "bp3-test";
                 "action";
                 "new-tab";
                 "--name";
                 "bp3:worker";
                 "--cwd";
                 "/tmp/work tree";
                 "--no-focus";
                 "--layout-string";
                 Workspace.tab_layout;
                 "--";
                 "/bin/sh";
                 "/tmp/private launch";
               ]
               (Workspace.tab_argv ~session:"bp3-test" ~execution_id:"worker"
                  ~worktree:"/tmp/work tree" ~launch_file:"/tmp/private launch")
           );
         ])
