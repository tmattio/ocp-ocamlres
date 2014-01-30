(* This file is part of ocp-ocamlres - subformats
 * (C) 2013 OCamlPro - Benjamin CANOU
 *
 * ocp-ocamlres is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3.0 of the License, or (at your option) any later version.
 * 
 * ocp-ocamlres is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public
 * License along with ocp-ocamlres.
 * If not, see <http://www.gnu.org/licenses/>. *)

(** The type of subformats, as passed to the format functors.

    This is basically an abstract type equipped with the functions
    that work on it as required by the formats. This type is the
    intermediate representation of resources at generation time.  It
    can be the same as the run-time type of the resources, but is not
    necessarily so. For instance, a subformat could parse a CSV file
    using a CSV library at generation time but produce OCaml arrays or
    records as output. See {!Int} for a simple sample instance.

    All functions take two extra parameters specifying the path and
    data of the processed resource. They are added for building
    decorator / dispatch subformats and should be ignored for most
    formats. *)
module type SubFormat = sig

  (** The generation-time intermediate representation of data. *)
  type t

  (** A parser as used by the scanner to obtain the in-memory
      resources from files. *)
  val from_raw : OCamlRes.Path.t -> string -> t
  (** A dumper to reconstitute the files from the in-memory
      resources. *)
  val to_raw : OCamlRes.Path.t -> t -> string

  (** Takes the current column, the expected line width, the path to
      the resource in the resource tree, and its value to pretty
      print. Returns the OCaml representation of the value. *)
  val pprint : int -> int -> OCamlRes.Path.t -> t -> PPrint.document
  (** Provides an optional piece of OCaml code to put before the
      resource store definition, for instance a type definition. *)
  val pprint_header : OCamlRes.Path.t -> t -> PPrint.document option
  (** Provides an optional piece of OCaml code to put after the
      resource store definition, for instance a type definition. *)
  val pprint_footer : OCamlRes.Path.t -> t -> PPrint.document option

  (** A name used to identify the subformat. *)
  val name : OCamlRes.Path.t -> t -> string
  (** The run-time OCaml type name (that describes the type of
      values generated by {!pprint}). Used to annotate the generated
      source where needed. The common usecase is when this function
      returns the same type as the static {!t} type. *)
  val type_name : OCamlRes.Path.t -> t -> string
  (** The name of the subformat module at run-time. If the static type
      {!t} is the same as the runtime type returned by {!type_abbrv},
      this is simply the path to the module used for generation.*)
  val mod_name : OCamlRes.Path.t -> t -> string
end

(** A probably useless subformat, for demonstration purposes *)
module Int = struct
  type t = int
  let from_raw _ str = Scanf.sscanf str "%i" (fun i -> i)
  let to_raw _ i = Printf.sprintf "%i" i

  let pprint col width _ i = PPrint.OCaml.int i
  let pprint_header _ _ = None
  let pprint_footer _ _ = None

  let name _ _ = "int"
  let type_name _ _ = "int"
  let mod_name _ _ = "OCamlResSubFormats.Int"
end

(** The default format (raw contents as a string) *)
module Raw = struct
  type t = string
  let from_raw _ raw_text = raw_text
  let to_raw _ raw_text = raw_text

  (** Splits a string into a flow of escaped characters. Respects
      the original line feeds if it ressembles a text file. *)
  let pprint col width path data =
    let open PPrint in
    let len = String.length data in
    let looks_like_text =
      let rec loop i acc =
        if i = len then
          acc <= len / 10 (* allow 10% of escaped chars *)
        else
          let c = Char.code data.[i] in
          if c < 32 && c <> 10 && c <> 13 && c <> 9 then false
          else if Char.code data.[i] >= 128 then loop (i + 1) (acc + 1)
          else loop (i + 1) acc
      in loop 0 0
    in
    let  hexd = [| '0' ; '1' ; '2' ; '3' ; '4' ; '5' ; '6' ; '7' ;
                   '8' ; '9' ; 'A' ; 'B' ; 'C' ; 'D' ; 'E' ; 'F' |] in
    if not looks_like_text then
      let cwidth = (width - col) / 4 in
      let rec split acc ofs =
        if ofs >= len then List.rev acc
        else
          let blen = min cwidth (len - ofs) in
          let blob = String.create (blen * 4) in
          for i = 0 to blen - 1 do
            let c = Char.code data.[ofs + i] in
            blob.[i * 4] <- '\\' ;
            blob.[i * 4 + 1] <- 'x' ;
            blob.[i * 4 + 2] <- (hexd.(c lsr 4)) ;
            blob.[i * 4 + 3] <- (hexd.(c land 15)) ;
          done ;
          let blob = if ofs <> 0 then !^" " ^^ !^blob else !^blob in
          split (blob :: acc) (ofs + blen)
      in
      !^"\"" ^^ separate (!^"\\" ^^ hardline) (split [] 0) ^^ !^"\""
    else
      let do_one_char cur next =
        match cur, next with
        | ' ', _ ->
          group (ifflat !^" " (!^"\\" ^^ hardline ^^ !^"\\ "))
        | '\r', '\n' ->
          group (ifflat !^"\\r" (!^"\\" ^^ hardline ^^ !^" \\r"))
        | '\r', ' ' ->
          ifflat !^"\\r"
            (group (ifflat !^"\\r" (!^"\\" ^^ hardline ^^ !^" \\r"))
             ^^ !^"\\" ^^ hardline ^^ !^"\\")
        | '\r', _ ->
          ifflat !^"\\r"
            (group (ifflat !^"\\r" (!^"\\" ^^ hardline ^^ !^" \\r"))
             ^^ !^"\\" ^^ hardline ^^ !^" ")
        | '\n', ' ' ->
          ifflat !^"\\n"
            (group (ifflat !^"\\n" (!^"\\" ^^ hardline ^^ !^" \\n"))
             ^^ !^"\\" ^^ hardline ^^ !^"\\")
        | '\n', _ ->
          ifflat !^"\\n"
            (group (ifflat !^"\\n" (!^"\\" ^^ hardline ^^ !^" \\n"))
             ^^ !^"\\" ^^ hardline ^^ !^" ")
        | '\t', _ ->
          group (ifflat !^"\\t" (!^"\\" ^^ hardline ^^ !^" \\t"))
        | '"', _ ->
          group (ifflat !^"\\\"" (!^"\\" ^^ hardline ^^ !^" \\\""))
        | '\\', _ ->
          group (ifflat !^"\\\\" (!^"\\" ^^ hardline ^^ !^" \\\\"))
        | c, _ ->
          let fmt =
            if Char.code c > 128 || Char.code c < 32 then
              let c = Char.code c in
              let s = String.create 4 in
              s.[0] <- '\\' ; s.[1] <- 'x' ;
              s.[2] <- (hexd.(c lsr 4)) ; s.[3] <- (hexd.(c land 15)) ;
              s
            else String.make 1 c
          in
          group (ifflat !^fmt (!^"\\" ^^ hardline ^^ !^" " ^^ !^fmt))
      in
      let res = ref empty in
      for i = 0 to len - 2 do
        res := !res ^^ do_one_char data.[i] data.[succ i]
      done ;
      if len > 0 then res := !res ^^ do_one_char data.[len - 1] '\000' ;
      group (!^"\"" ^^ !res ^^ !^"\"")
  let pprint_header _ _ = None
  let pprint_footer _ _ = None

  let name _ _ = "raw"
  let type_name _ _ = "string"
  let mod_name _ _ = "OCamlResSubFormats.Raw"
end

(** Splits the input into lines *)
module Lines = struct
  type t = string list
  let from_raw _ str = Str.split (Str.regexp "[\r\n]") str
  let to_raw _ lines = String.concat "\n" lines

  let pprint col width path lns =
    let open PPrint in
    let contents =
      separate_map
        (!^" ;" ^^ break 1)
        (fun l -> column (fun col -> Raw.pprint col width path l))
        lns
    in group (!^"[ " ^^ nest 2 contents ^^ !^" ]")
  let pprint_header _ _ = None
  let pprint_footer _ _ = None

  let name _ _ = "lines"
  let type_name _ _ = "string list"
  let mod_name _ _ = "OCamlResSubFormats.Lines"
end