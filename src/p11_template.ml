type t = P11_attribute.pack list

let to_yojson template :Yojson.Safe.json =
  let attributes = List.map (fun (P11_attribute.Pack x) -> P11_attribute.to_json x) template in
  let flatten_attribute = function
    | `Assoc l -> l
    | _ -> assert false (* All attributes are represented using [`Assoc]. *)
  in
  let attributes = List.map flatten_attribute attributes |> List.flatten in
  `Assoc attributes

let of_yojson json =
  let open Ppx_deriving_yojson_runtime in
  match json with
    | `Assoc assoc ->
        begin
          let attributes = List.map (fun (a, b) -> `Assoc [ a, b ]) assoc in
          map_bind P11_attribute.pack_of_yojson [] attributes
        end
    | _ -> Error "Ill-formed template"

let rec get : type a . t -> a P11_attribute_type.t -> a option = fun template x ->
  match template with
    | [] -> None
    | head :: tail ->
        match head with
          | P11_attribute.Pack (ty,v) ->
              match Pkcs11.CK_ATTRIBUTE_TYPE.compare' ty x with
                | Pkcs11.CK_ATTRIBUTE_TYPE.Equal -> Some v
                | Pkcs11.CK_ATTRIBUTE_TYPE.Not_equal _ -> get tail x

let get_pack template (P11_attribute_type.Pack ty) =
  match get template ty with
    | None -> None
    | Some v -> Some (P11_attribute.Pack (ty,v))

let of_raw = Pkcs11.Template.view

(** [normalize t] returns a normal form for the template [t]. That
    is, a template that is sorted. *)
let normalize (t:t) : t =
  List.sort P11_attribute.compare_pack t

(** compares two normalized templates  *)
let rec compare a b =
  match a,b with
    | [], [] -> 0
    | [], _::_ -> -1
    | _::_, [] -> 1
    | a1::a2, b1::b2 ->
        let cmp = P11_attribute.compare_pack a1 b1 in
        if cmp = 0
        then compare a2 b2
        else cmp

(** safe mem on templates. *)
let mem elem = List.exists (P11_attribute.equal_pack elem)

(* Operations  *)
let fold = List.fold_right

(* Replace the value of [attribute] in [template] if it already
   exists.  Add [attribute] otherwise. *)
let set_attribute attribute (template : P11_attribute.pack list) =
  let exists = ref false in
  let replace_value old_attribute =
    if
      P11_attribute.compare_types_pack old_attribute attribute = 0
    then
      (exists := true; attribute)
    else
      old_attribute
  in
  let template = List.map replace_value template in
  if !exists then
    template
  else
    attribute :: template

let remove_attribute attribute template =
  List.filter (fun x -> not (P11_attribute.equal_pack x attribute)) template

let remove_attribute_type attribute_type template =
  List.filter (fun x ->
      let x = P11_attribute.type_ x in
      not (P11_attribute_type.equal_pack x attribute_type)) template

let attribute_types template =
  List.map P11_attribute.type_ template

let union template1 template2 =
  List.fold_left
    (fun template attribute -> set_attribute attribute template)
    template2
    (List.rev template1)

let only_attribute_types types template =
  List.fold_left (fun template attribute ->
      let type_ = P11_attribute.type_ attribute in
      if List.exists (P11_attribute_type.equal_pack type_) types
      then attribute::template
      else template
    ) [] template
  |> List.rev

let except_attribute_types types template =
  List.fold_left (fun template attribute ->
      let type_ = P11_attribute.type_ attribute in
      if List.exists (P11_attribute_type.equal_pack type_) types
      then template
      else attribute:: template
    ) [] template
  |> List.rev

let find_attribute_types types template =
  let rec aux types result =
    match types with
      | [] -> Some (List.rev result)
      | ty::q ->
          begin match get_pack template ty with
            | None -> None
            | Some a -> aux q (a::result)
          end
  in
  aux types []

let correspond ~source ~tested =
  (* For all the elements of source, check if an element in tested
     correspond. *)
  List.for_all
    (fun x -> List.exists (P11_attribute.equal_pack x) tested)
    source

(** For all the elements of source, check if an element in tested
    correspond. Return a tuple with the list of elements from source
    which are expected but not found in tested and a list of elements
    which are found but with a different value.
*)
let diff ~source ~tested =
  let empty = ([], []) in
  List.fold_left (
    fun
      (missing, different)
      (P11_attribute.Pack (attribute, a_value) as pack) ->
      match get tested attribute with
        | None ->
            let missing = pack :: missing in
            missing, different
        | Some value ->
            let different =
              if a_value = value then
                different
              else
                pack :: different
            in
            missing, different
  ) empty source

let to_string t =
  to_yojson t |> Yojson.Safe.to_string

let pp fmt t = Format.fprintf fmt "%s" @@ to_string t

let hash t =
  normalize t |> to_string |> Digest.string

let get_class t = get t P11_attribute_type.CKA_CLASS
let get_key_type t = get t P11_attribute_type.CKA_KEY_TYPE
let get_label t = get t P11_attribute_type.CKA_LABEL
