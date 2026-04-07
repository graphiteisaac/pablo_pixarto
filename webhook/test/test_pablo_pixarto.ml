(* Set up the mock values *)

let mock_db_path = "mock_db.json"
let mock_time = 123456789

let make_mock_db () =
  print_endline "Creating mock db...";
  let path = Filename.concat (Sys.getcwd ()) mock_db_path in
  let oc = open_out path in
  Printf.fprintf oc "{\"lastUpdate\":0,\"posts\":[]}";
  close_out oc;
  print_endline "Done creating mock db."

let mock_db () = `Assoc [ ("lastUpdate", `Int 0); ("posts", `List []) ]

(* Database tests *)
let test_empty_db () =
  match Pablo_pixarto.db_of_yojson (mock_db ()) with
  | Error e -> Alcotest.fail e
  | Ok db ->
      Alcotest.(check int) "last_update" 0 db.last_update;
      Alcotest.(check (list string)) "posts" [] db.posts

let test_write_to_db () =
  let db =
    Pablo_pixarto.{ last_update = mock_time; posts = [ "https://google.com" ] }
  in
  Pablo_pixarto.save_db mock_db_path db

let test_read_updated_db () =
  let db = Pablo_pixarto.load_db mock_db_path in
  Alcotest.(check int) "last_update" mock_time db.last_update;
  Alcotest.(check (list string)) "posts" [ "https://google.com" ] db.posts

let () =
  make_mock_db ();
  let open Alcotest in
  run "Units"
    [
      ( "database",
        [
          test_case "parses empty db" `Quick test_empty_db;
          test_case "can write to db" `Quick test_write_to_db;
          test_case "reads db back correectly" `Quick test_read_updated_db;
        ] );
    ]
