(** An attribute is a single parameter of a key template. An
    attribute can hold a Boolean value, a string value, a key type
    value, and so on and so forth. They are pervasively used in the
    PKCS11 API, and are one of the most tricky part of the PKCS11
    interface.

    There are two different use patterns for attributes.

    - The user may set up a list of attribute (e.g., set CKA_TRUSTED to
    true and CKA_ENCRYPT to false) and use this list as input for a
    given function. The list will never be read again by the user.

    - The user may set up a list of attribute types (e.g. CKA_TRUSTED,
    CKA_ENCRYPT, CKA_LABEL) and query the API for the values of these
    attributes. This query is a two step process in which the user first
    set up an array of empty attributes with right type value (the CKA_
    constants). The user make a call to C_GetAttributeValue which sets
    up the correct size for each attribute. Then the user must allocate
    enough memory for each attribute and make another call. At the end
    of this call, each attribute contains the right value.

    We can expose "safe" bindings in the following way. We define
    [Attribute.u] as a variant. The user can use user-friendly templates
    (e.g. lists of Attribute.u) as inputs for functions that do not
    modifiy the templates. We provide a wrapper around functions that
    modifies the templates, so that they take as input a list of
    AttributeType.t (i.e., the manifest constants that are used to
    describe attributes) and they return a list of Attribute.u.
*)

open Ctypes
open Ctypes_helpers
open Result

type _t
type t = _t structure
let ck_attribute : _t structure typ = structure "CK_ATTRIBUTE"
let (-:) ty label = smart_field ck_attribute label ty
let _type = Pkcs11_CK_ATTRIBUTE_TYPE.typ -: "type"
let pValue = Reachable_ptr.typ void -: "pValue"
let ulValueLen = ulong -: "ulValueLen"
let () = seal ck_attribute

type 'a u = 'a Pkcs11_CK_ATTRIBUTE_TYPE.u * 'a
type pack = Pack : 'a u -> pack

(** [create cka] allocates a new struct and set the [attribute_type]
    field to [cka]. The value and its length are both initialised to
    default values. *)
let create attribute_type : t =
  let a = Ctypes.make ck_attribute in
  setf a _type attribute_type;
  Reachable_ptr.setf a pValue null;
  setf a ulValueLen (Unsigned.ULong.zero);
  a

(** [allocate t] updates the structure in place by allocating memory
    for the value. *)
let allocate (t: t) : unit =
  let count = Unsigned.ULong.to_int  (getf t ulValueLen) in
  Reachable_ptr.setf t pValue (to_voidp (allocate_n (char) ~count));
  ()

let get_type t =
  getf t _type

let get_length t =
  Unsigned.ULong.to_int (getf t ulValueLen)

let pvalue_is_null_ptr t = is_null (Reachable_ptr.getf t pValue)

let unsafe_get_value typ t =
  from_voidp typ (Reachable_ptr.getf t pValue)

let ck_true : Pkcs11_CK_BBOOL.t ptr = Ctypes.allocate Pkcs11_CK_BBOOL.typ Pkcs11_CK_BBOOL._CK_TRUE
let ck_false : Pkcs11_CK_BBOOL.t ptr = Ctypes.allocate Pkcs11_CK_BBOOL.typ Pkcs11_CK_BBOOL._CK_FALSE

(* Constructors *)

let boolean attribute_type bool : t =
  let a = Ctypes.make ck_attribute in
  let bool = if bool then ck_true else ck_false in
  setf a _type attribute_type;
  Reachable_ptr.setf a pValue (to_voidp bool);
  setf a ulValueLen (Unsigned.ULong.of_int (sizeof uint8_t));
  a

let byte attribute_type byte : t =
  let a = Ctypes.make ck_attribute in
  let byte = Ctypes.allocate Ctypes.uint8_t (Unsigned.UInt8.of_int byte) in
  setf a _type attribute_type;
  Reachable_ptr.setf a pValue (to_voidp byte);
  setf a ulValueLen (Unsigned.ULong.of_int (sizeof uint8_t));
  a

let ulong attribute_type ulong : t =
  let a = Ctypes.make ck_attribute in
  let ulong = Ctypes.allocate Ctypes.ulong ulong in
  setf a _type attribute_type;
  Reachable_ptr.setf a pValue (to_voidp ulong);
  setf a ulValueLen (Unsigned.ULong.of_int (sizeof Ctypes.ulong));
  a

let string attribute_type string : t =
  let a = Ctypes.make ck_attribute in
  let s = ptr_from_string string in
  setf a _type attribute_type;
  Reachable_ptr.setf a pValue (to_voidp s);
  setf a ulValueLen (Unsigned.ULong.of_int (String.length string));
  a

let bigint attr_type u =
  string attr_type (Pkcs11_CK_BIGINT.encode u)

(* Accessors *)

let unsafe_get_bool t =
  let p = unsafe_get_value uint8_t t in
  let b = !@ p in
  Unsigned.UInt8.to_int b <> 0

let unsafe_get_byte t =
  let p = unsafe_get_value uint8_t t in
  let b = !@ p in
  Unsigned.UInt8.to_int b

(** [unsafe_get_string] reads the length of the string in [t], so it
    is able to handle string with \000 inside. *)
let unsafe_get_string t =
  let length = get_length t in
  let p  = unsafe_get_value char t in
  string_from_ptr p ~length

let unsafe_get_ulong t =
  let p = unsafe_get_value Ctypes.ulong t in
  !@ p

let unsafe_get_object_class : t -> Pkcs11_CK_OBJECT_CLASS.t =
  unsafe_get_ulong

let unsafe_get_key_type : t -> Pkcs11_CK_KEY_TYPE.t =
  unsafe_get_ulong

let unsafe_get_bigint t =
  Pkcs11_CK_BIGINT.decode (unsafe_get_string t)

let decode_ec_point cs =
  let grammar = Key_parsers.Asn1.EC.point_grammar in
  let codec = Asn.codec Asn.ber grammar in
  match Asn.decode codec cs with
    | None -> Error "Parse error"
    | Some (r, leftover) when Cstruct.len leftover <> 0 ->
        Error ("CKA_EC_POINT: leftover")
    | Some (r, _) -> Ok r

(**
   Pack the specified attribute, but if decoding fails, log the error and return
   an CKA_CS_UNKNOWN attribute.
 *)
let decode_cka attr_type decode s =
  match decode @@ Cstruct.of_string s with
    | Ok p -> Pack (attr_type, p)
    | Error e ->
        begin
          let open Pkcs11_CK_ATTRIBUTE_TYPE in
          let name = to_string attr_type in
          Pkcs11_log.log @@ Printf.sprintf "Invalid %s: %S (error: %S)" name s e;
          let code = CKA_CS_UNKNOWN (make attr_type) in
          let value = NOT_IMPLEMENTED s in
          Pack (code, value)
        end

let decode_cka_ec_point s =
  decode_cka Pkcs11_CK_ATTRIBUTE_TYPE.CKA_EC_POINT decode_ec_point s

let decode_cka_ec_params s =
  decode_cka Pkcs11_CK_ATTRIBUTE_TYPE.CKA_EC_PARAMS Key_parsers.Asn1.EC.Params.decode s

let encode_asn grammar x =
  let codec = Asn.codec Asn.der grammar in
  Cstruct.to_string @@ Asn.encode codec x

let encode_ec_params = encode_asn Key_parsers.Asn1.EC.Params.grammar
let encode_ec_point = encode_asn Key_parsers.Asn1.EC.point_grammar

let view (t : t) : pack =
  let ul = getf t _type in
  let open Pkcs11_CK_ATTRIBUTE_TYPE in
  if ul ==  _CKA_CLASS                              then Pack (CKA_CLASS, (unsafe_get_object_class t |> Pkcs11_CK_OBJECT_CLASS.view))
  else if ul ==  _CKA_TOKEN                         then Pack (CKA_TOKEN, (unsafe_get_bool t))
  else if ul ==  _CKA_PRIVATE                       then Pack (CKA_PRIVATE, (unsafe_get_bool t))
  else if ul ==  _CKA_LABEL                         then Pack (CKA_LABEL, (unsafe_get_string t))
  else if ul ==  _CKA_VALUE                         then Pack (CKA_VALUE, (unsafe_get_string t))
  else if ul ==  _CKA_TRUSTED                       then Pack (CKA_TRUSTED, (unsafe_get_bool t))
  else if ul ==  _CKA_KEY_TYPE                      then Pack (CKA_KEY_TYPE, (unsafe_get_key_type t |> Pkcs11_CK_KEY_TYPE.view))
  else if ul ==  _CKA_SUBJECT                       then Pack (CKA_SUBJECT,  (unsafe_get_string t))
  else if ul ==  _CKA_ID                            then Pack (CKA_ID,       (unsafe_get_string t))
  else if ul ==  _CKA_SENSITIVE                     then Pack (CKA_SENSITIVE, (unsafe_get_bool t))
  else if ul ==  _CKA_ENCRYPT                       then Pack (CKA_ENCRYPT, (unsafe_get_bool t))
  else if ul ==  _CKA_DECRYPT                       then Pack (CKA_DECRYPT, (unsafe_get_bool t))
  else if ul ==  _CKA_WRAP                          then Pack (CKA_WRAP, (unsafe_get_bool t))
  else if ul ==  _CKA_UNWRAP                        then Pack (CKA_UNWRAP, (unsafe_get_bool t))
  else if ul ==  _CKA_SIGN                          then Pack (CKA_SIGN, (unsafe_get_bool t))
  else if ul ==  _CKA_SIGN_RECOVER                  then Pack (CKA_SIGN_RECOVER, (unsafe_get_bool t))
  else if ul ==  _CKA_VERIFY                        then Pack (CKA_VERIFY, (unsafe_get_bool t))
  else if ul ==  _CKA_VERIFY_RECOVER                then Pack (CKA_VERIFY_RECOVER, (unsafe_get_bool t))
  else if ul ==  _CKA_DERIVE                        then Pack (CKA_DERIVE, (unsafe_get_bool t))
  else if ul ==  _CKA_MODULUS                       then Pack (CKA_MODULUS, (unsafe_get_bigint t))
  else if ul ==  _CKA_MODULUS_BITS                  then Pack (CKA_MODULUS_BITS, (unsafe_get_ulong t))
  else if ul ==  _CKA_PUBLIC_EXPONENT               then Pack (CKA_PUBLIC_EXPONENT, (unsafe_get_bigint t))
  else if ul ==  _CKA_PRIVATE_EXPONENT              then Pack (CKA_PRIVATE_EXPONENT, (unsafe_get_bigint t))
  else if ul ==  _CKA_PRIME_1                       then Pack (CKA_PRIME_1, (unsafe_get_bigint t))
  else if ul ==  _CKA_PRIME_2                       then Pack (CKA_PRIME_2, (unsafe_get_bigint t))
  else if ul ==  _CKA_EXPONENT_1                    then Pack (CKA_EXPONENT_1, (unsafe_get_bigint t))
  else if ul ==  _CKA_EXPONENT_2                    then Pack (CKA_EXPONENT_2, (unsafe_get_bigint t))
  else if ul ==  _CKA_COEFFICIENT                   then Pack (CKA_COEFFICIENT, (unsafe_get_bigint t))
  else if ul ==  _CKA_PRIME                         then Pack (CKA_PRIME, (unsafe_get_bigint t))
  else if ul ==  _CKA_SUBPRIME                      then Pack (CKA_SUBPRIME, (unsafe_get_bigint t))
  else if ul ==  _CKA_PRIME_BITS                    then Pack (CKA_PRIME_BITS, unsafe_get_ulong t)
  else if ul ==  _CKA_SUBPRIME_BITS                 then Pack (CKA_SUBPRIME_BITS, unsafe_get_ulong t)
  else if ul ==  _CKA_VALUE_LEN                     then Pack (CKA_VALUE_LEN, (unsafe_get_ulong t))
  else if ul ==  _CKA_EXTRACTABLE                   then Pack (CKA_EXTRACTABLE, (unsafe_get_bool t))
  else if ul ==  _CKA_LOCAL                         then Pack (CKA_LOCAL, (unsafe_get_bool t))
  else if ul ==  _CKA_NEVER_EXTRACTABLE             then Pack (CKA_NEVER_EXTRACTABLE, (unsafe_get_bool t))
  else if ul ==  _CKA_ALWAYS_SENSITIVE              then Pack (CKA_ALWAYS_SENSITIVE, (unsafe_get_bool t))
  else if ul ==  _CKA_KEY_GEN_MECHANISM             then Pack (CKA_KEY_GEN_MECHANISM, Pkcs11_key_gen_mechanism.view (unsafe_get_ulong t))
  else if ul ==  _CKA_MODIFIABLE                    then Pack (CKA_MODIFIABLE, (unsafe_get_bool t))
  (* else if ul ==  _CKA_ECDSA_PARAMS                  then Pack (CKA_ECDSA_PARAMS, (unsafe_get_string t)) *)
  else if ul ==  _CKA_EC_PARAMS                     then decode_cka_ec_params (unsafe_get_string t)
  else if ul ==  _CKA_EC_POINT                      then decode_cka_ec_point (unsafe_get_string t)
  else if ul ==  _CKA_ALWAYS_AUTHENTICATE           then Pack (CKA_ALWAYS_AUTHENTICATE, (unsafe_get_bool t))
  else if ul ==  _CKA_WRAP_WITH_TRUSTED             then Pack (CKA_WRAP_WITH_TRUSTED,   (unsafe_get_bool t))
  else
    begin
      Pkcs11_log.log @@ Printf.sprintf "Unknown CKA code: 0x%Lx" @@ Int64.of_string @@ Unsigned.ULong.to_string ul;
      Pack (CKA_CS_UNKNOWN ul, NOT_IMPLEMENTED (unsafe_get_string t))
    end

(* Useful regexp |\(.*\) of string -> | \1 s -> string AttributesType.\1 s): *)

let make : type s . s u -> t = fun x ->
  let open Pkcs11_CK_ATTRIBUTE_TYPE in
  match x with
  | CKA_CLASS, cko -> ulong Pkcs11_CK_ATTRIBUTE_TYPE._CKA_CLASS (Pkcs11_CK_OBJECT_CLASS.make cko)
  | CKA_TOKEN, b -> boolean Pkcs11_CK_ATTRIBUTE_TYPE._CKA_TOKEN b
  | CKA_PRIVATE, b -> boolean Pkcs11_CK_ATTRIBUTE_TYPE._CKA_PRIVATE b
  | CKA_LABEL, s -> string Pkcs11_CK_ATTRIBUTE_TYPE._CKA_LABEL s
  | CKA_VALUE, s -> string Pkcs11_CK_ATTRIBUTE_TYPE._CKA_VALUE s
  | CKA_TRUSTED, b -> boolean Pkcs11_CK_ATTRIBUTE_TYPE._CKA_TRUSTED b
  | CKA_KEY_TYPE, ckk -> ulong Pkcs11_CK_ATTRIBUTE_TYPE._CKA_KEY_TYPE (Pkcs11_CK_KEY_TYPE.make ckk)
  | CKA_SUBJECT, s -> string Pkcs11_CK_ATTRIBUTE_TYPE._CKA_SUBJECT s
  | CKA_ID, s -> string Pkcs11_CK_ATTRIBUTE_TYPE._CKA_ID s
  | CKA_SENSITIVE, b -> boolean Pkcs11_CK_ATTRIBUTE_TYPE._CKA_SENSITIVE b
  | CKA_ENCRYPT,   b -> boolean Pkcs11_CK_ATTRIBUTE_TYPE._CKA_ENCRYPT   b
  | CKA_DECRYPT,   b -> boolean Pkcs11_CK_ATTRIBUTE_TYPE._CKA_DECRYPT   b
  | CKA_WRAP, b -> boolean Pkcs11_CK_ATTRIBUTE_TYPE._CKA_WRAP b
  | CKA_UNWRAP, b -> boolean Pkcs11_CK_ATTRIBUTE_TYPE._CKA_UNWRAP b
  | CKA_SIGN, b -> boolean Pkcs11_CK_ATTRIBUTE_TYPE._CKA_SIGN b
  | CKA_SIGN_RECOVER, b -> boolean Pkcs11_CK_ATTRIBUTE_TYPE._CKA_SIGN_RECOVER b
  | CKA_VERIFY, b -> boolean Pkcs11_CK_ATTRIBUTE_TYPE._CKA_VERIFY b
  | CKA_VERIFY_RECOVER, b -> boolean Pkcs11_CK_ATTRIBUTE_TYPE._CKA_VERIFY_RECOVER b
  | CKA_DERIVE, b -> boolean Pkcs11_CK_ATTRIBUTE_TYPE._CKA_DERIVE b
  | CKA_MODULUS, n -> bigint Pkcs11_CK_ATTRIBUTE_TYPE._CKA_MODULUS n
  | CKA_MODULUS_BITS,     ul -> ulong Pkcs11_CK_ATTRIBUTE_TYPE._CKA_MODULUS_BITS     ul
  | CKA_PUBLIC_EXPONENT, n -> bigint Pkcs11_CK_ATTRIBUTE_TYPE._CKA_PUBLIC_EXPONENT n
  | CKA_PRIVATE_EXPONENT, n -> bigint Pkcs11_CK_ATTRIBUTE_TYPE._CKA_PRIVATE_EXPONENT n
  | CKA_PRIME_1, n -> bigint Pkcs11_CK_ATTRIBUTE_TYPE._CKA_PRIME_1 n
  | CKA_PRIME_2, n -> bigint Pkcs11_CK_ATTRIBUTE_TYPE._CKA_PRIME_2 n
  | CKA_EXPONENT_1, n -> bigint Pkcs11_CK_ATTRIBUTE_TYPE._CKA_EXPONENT_1 n
  | CKA_EXPONENT_2, n -> bigint Pkcs11_CK_ATTRIBUTE_TYPE._CKA_EXPONENT_2 n
  | CKA_COEFFICIENT, n -> bigint Pkcs11_CK_ATTRIBUTE_TYPE._CKA_COEFFICIENT n
  | CKA_PRIME, n -> bigint Pkcs11_CK_ATTRIBUTE_TYPE._CKA_PRIME n
  | CKA_SUBPRIME, n -> bigint Pkcs11_CK_ATTRIBUTE_TYPE._CKA_SUBPRIME n
  | CKA_PRIME_BITS, ul -> ulong Pkcs11_CK_ATTRIBUTE_TYPE._CKA_PRIME_BITS ul
  | CKA_SUBPRIME_BITS, ul -> ulong Pkcs11_CK_ATTRIBUTE_TYPE._CKA_SUBPRIME_BITS ul
  | CKA_VALUE_LEN, ul -> ulong Pkcs11_CK_ATTRIBUTE_TYPE._CKA_VALUE_LEN ul
  | CKA_EXTRACTABLE, b -> boolean Pkcs11_CK_ATTRIBUTE_TYPE._CKA_EXTRACTABLE b
  | CKA_LOCAL,  b -> boolean Pkcs11_CK_ATTRIBUTE_TYPE._CKA_LOCAL  b
  | CKA_NEVER_EXTRACTABLE, b -> boolean Pkcs11_CK_ATTRIBUTE_TYPE._CKA_NEVER_EXTRACTABLE b
  | CKA_ALWAYS_SENSITIVE, b -> boolean Pkcs11_CK_ATTRIBUTE_TYPE._CKA_ALWAYS_SENSITIVE b
  | CKA_KEY_GEN_MECHANISM, m ->
      Pkcs11_key_gen_mechanism.make m
      |> ulong Pkcs11_CK_ATTRIBUTE_TYPE._CKA_KEY_GEN_MECHANISM
  | CKA_MODIFIABLE, b -> boolean Pkcs11_CK_ATTRIBUTE_TYPE._CKA_MODIFIABLE b
  (* | CKA_ECDSA_PARAMS, s -> string Pkcs11_CK_ATTRIBUTE_TYPE._CKA_ECDSA_PARAMS s *)
  | CKA_EC_PARAMS, p ->
      encode_ec_params p |> string Pkcs11_CK_ATTRIBUTE_TYPE._CKA_EC_PARAMS
  | CKA_EC_POINT, p -> encode_ec_point p |> string Pkcs11_CK_ATTRIBUTE_TYPE._CKA_EC_POINT
  | CKA_ALWAYS_AUTHENTICATE, b -> boolean Pkcs11_CK_ATTRIBUTE_TYPE._CKA_ALWAYS_AUTHENTICATE b
  | CKA_WRAP_WITH_TRUSTED,   b -> boolean Pkcs11_CK_ATTRIBUTE_TYPE._CKA_WRAP_WITH_TRUSTED   b
  | CKA_CS_UNKNOWN ul, NOT_IMPLEMENTED s ->
      string ul s

let make_pack (Pack x) = make x

let to_string_pair =
  let ulong cka x = cka, Unsigned.ULong.to_string x in
  let object_class cka cko = cka, Pkcs11_CK_OBJECT_CLASS.to_string cko in
  let bool cka x = cka, if x then "CK_TRUE" else "CK_FALSE" in
  let string cka x = cka, Printf.sprintf "%S" x in
  let key_type cka ckk = cka, Pkcs11_CK_KEY_TYPE.to_string ckk in
  let mechanism_type cka x = cka, Pkcs11_key_gen_mechanism.to_string x in
  let ec_parameters cka x = cka, Key_parsers.Asn1.EC.Params.show x in
  let ec_point cka x = cka, Key_parsers.Asn1.EC.show_point x in
  let bigint cka x = cka, Pkcs11_CK_BIGINT.to_string x in
  fun (type s) (x : s u) ->
    let open Pkcs11_CK_ATTRIBUTE_TYPE in
    match x with
      | CKA_CLASS, x               -> object_class "CKA_CLASS" x
      | CKA_TOKEN, x               -> bool "CKA_TOKEN" x
      | CKA_PRIVATE, x             -> bool "CKA_PRIVATE" x
      | CKA_LABEL, x               -> string "CKA_LABEL" x
      | CKA_VALUE, x               -> string "CKA_VALUE" x
      | CKA_TRUSTED, x             -> bool "CKA_TRUSTED" x
      | CKA_KEY_TYPE, x            -> key_type "CKA_KEY_TYPE" x
      | CKA_SUBJECT, x             -> string "CKA_SUBJECT" x
      | CKA_ID, x                  -> string "CKA_ID" x
      | CKA_SENSITIVE, x           -> bool "CKA_SENSITIVE" x
      | CKA_ENCRYPT,   x           -> bool "CKA_ENCRYPT" x
      | CKA_DECRYPT,   x           -> bool "CKA_DECRYPT" x
      | CKA_WRAP, x                -> bool "CKA_WRAP" x
      | CKA_UNWRAP, x              -> bool "CKA_UNWRAP" x
      | CKA_SIGN, x                -> bool "CKA_SIGN" x
      | CKA_SIGN_RECOVER, x        -> bool "CKA_SIGN_RECOVER" x
      | CKA_VERIFY, x              -> bool "CKA_VERIFY" x
      | CKA_VERIFY_RECOVER, x      -> bool "CKA_VERIFY_RECOVER" x
      | CKA_DERIVE, x              -> bool "CKA_DERIVE" x
      | CKA_MODULUS,  x            -> bigint "CKA_MODULUS" x
      | CKA_MODULUS_BITS,     x    -> ulong "CKA_MODULUS_BITS" x
      | CKA_PUBLIC_EXPONENT,  x    -> bigint "CKA_PUBLIC_EXPONENT" x
      | CKA_PRIVATE_EXPONENT, x    -> bigint "CKA_PRIVATE_EXPONENT" x
      | CKA_PRIME_1,          x    -> bigint "CKA_PRIME_1" x
      | CKA_PRIME_2,          x    -> bigint "CKA_PRIME_2" x
      | CKA_EXPONENT_1,       x    -> bigint "CKA_EXPONENT_1" x
      | CKA_EXPONENT_2,       x    -> bigint "CKA_EXPONENT_2" x
      | CKA_COEFFICIENT,      x    -> bigint "CKA_COEFFICIENT" x
      | CKA_PRIME,            x    -> bigint "CKA_PRIME" x
      | CKA_SUBPRIME,         x    -> bigint "CKA_SUBPRIME" x
      | CKA_PRIME_BITS,  x          -> ulong "CKA_PRIME_BITS" x
      | CKA_SUBPRIME_BITS, x        -> ulong "CKA_SUBPRIME_BITS" x
      | CKA_VALUE_LEN, x           -> ulong "CKA_VALUE_LEN" x
      | CKA_EXTRACTABLE, x         -> bool "CKA_EXTRACTABLE" x
      | CKA_LOCAL,  x              -> bool "CKA_LOCAL" x
      | CKA_NEVER_EXTRACTABLE, x   -> bool "CKA_NEVER_EXTRACTABLE" x
      | CKA_ALWAYS_SENSITIVE, x    -> bool "CKA_ALWAYS_SENSITIVE" x
      | CKA_KEY_GEN_MECHANISM, x   -> mechanism_type "CKA_KEY_GEN_MECHANISM" x
      | CKA_MODIFIABLE, x          -> bool "CKA_MODIFIABLE" x
      (* | CKA_ECDSA_PARAMS, x        -> string "CKA_ECDSA_PARAMS" x *)
      | CKA_EC_PARAMS, x           -> ec_parameters "CKA_EC_PARAMS" x
      | CKA_EC_POINT, x            -> ec_point "CKA_EC_POINT" x
      | CKA_ALWAYS_AUTHENTICATE, x -> bool "CKA_ALWAYS_AUTHENTICATE" x
      | CKA_WRAP_WITH_TRUSTED,   x -> bool "CKA_WRAP_WITH_TRUSTED" x
      | CKA_CS_UNKNOWN ul, NOT_IMPLEMENTED x -> string (Unsigned.ULong.to_string ul) x

let to_string x =
  let a, b = to_string_pair x in
  Printf.sprintf "%s %s" a b

let compare_types (a,_) (b,_) =
  Pkcs11_CK_ATTRIBUTE_TYPE.compare a b

let compare_types_pack (Pack(a,_)) (Pack(b,_)) = Pkcs11_CK_ATTRIBUTE_TYPE.compare a b

let compare_bool (x : bool) (y : bool) = compare x y
let compare_string (x : string) (y : string) = compare x y
let compare_ulong = Unsigned.ULong.compare
let compare : type a b. a u -> b u -> int = fun a b ->
  let open Pkcs11_CK_ATTRIBUTE_TYPE in
  let c = compare_types a b in
  if c <> 0 then
    c
  else
    (* This match raises warning 4 in a spurious manner. The first
       component of the match would be non-exhaustive if we added a
       new constructor to the the type. The system is not smart
       enough to detect that the right part (which would become
       non-exhaustive) is related to the left part. *)
    match[@ocaml.warning "-4"] a, b with
      | (CKA_CLASS, a_param), (CKA_CLASS, b_param) ->
          Pkcs11_CK_OBJECT_CLASS.compare a_param b_param
      | (CKA_KEY_TYPE, a_param), (CKA_KEY_TYPE, b_param) ->
          Pkcs11_CK_KEY_TYPE.compare a_param b_param
      | (CKA_MODULUS_BITS, a_param), (CKA_MODULUS_BITS, b_param) ->
          Pkcs11_CK_ULONG.compare a_param b_param
      | (CKA_VALUE_LEN, a_param), (CKA_VALUE_LEN, b_param) ->
          Pkcs11_CK_ULONG.compare a_param b_param
      | (CKA_KEY_GEN_MECHANISM, a_param), (CKA_KEY_GEN_MECHANISM, b_param) ->
          Pkcs11_key_gen_mechanism.compare a_param b_param
      | (CKA_EC_PARAMS, a_param), (CKA_EC_PARAMS, b_param) ->
          Key_parsers.Asn1.EC.Params.compare a_param b_param
      | (CKA_EC_POINT, a_param), (CKA_EC_POINT, b_param) ->
          Key_parsers.Asn1.EC.compare_point a_param b_param
      | (CKA_PUBLIC_EXPONENT, a_param), (CKA_PUBLIC_EXPONENT, b_param) -> Pkcs11_CK_BIGINT.compare a_param b_param
      | (CKA_PRIVATE_EXPONENT, a_param), (CKA_PRIVATE_EXPONENT, b_param) -> Pkcs11_CK_BIGINT.compare a_param b_param
      | (CKA_PRIME_1, a_param), (CKA_PRIME_1, b_param) -> Pkcs11_CK_BIGINT.compare a_param b_param
      | (CKA_PRIME_2, a_param), (CKA_PRIME_2, b_param) -> Pkcs11_CK_BIGINT.compare a_param b_param
      | (CKA_EXPONENT_1, a_param), (CKA_EXPONENT_1, b_param) -> Pkcs11_CK_BIGINT.compare a_param b_param
      | (CKA_EXPONENT_2, a_param), (CKA_EXPONENT_2, b_param) -> Pkcs11_CK_BIGINT.compare a_param b_param
      | (CKA_COEFFICIENT, a_param), (CKA_COEFFICIENT, b_param) -> Pkcs11_CK_BIGINT.compare a_param b_param
      | (CKA_PRIME, a_param), (CKA_PRIME, b_param) -> Pkcs11_CK_BIGINT.compare a_param b_param
      | (CKA_SUBPRIME, a_param), (CKA_SUBPRIME, b_param) -> Pkcs11_CK_BIGINT.compare a_param b_param
      | (CKA_MODULUS, a_param), (CKA_MODULUS, b_param) -> Pkcs11_CK_BIGINT.compare a_param b_param

      | (CKA_TOKEN, a_param), (CKA_TOKEN, b_param) -> compare_bool a_param b_param
      | (CKA_PRIVATE, a_param), (CKA_PRIVATE, b_param) -> compare_bool a_param b_param
      | (CKA_TRUSTED, a_param), (CKA_TRUSTED, b_param) -> compare_bool a_param b_param
      | (CKA_SENSITIVE, a_param), (CKA_SENSITIVE, b_param) -> compare_bool a_param b_param
      | (CKA_ENCRYPT, a_param), (CKA_ENCRYPT, b_param) -> compare_bool a_param b_param
      | (CKA_DECRYPT, a_param), (CKA_DECRYPT, b_param) -> compare_bool a_param b_param
      | (CKA_WRAP, a_param), (CKA_WRAP, b_param) -> compare_bool a_param b_param
      | (CKA_UNWRAP, a_param), (CKA_UNWRAP, b_param) -> compare_bool a_param b_param
      | (CKA_SIGN, a_param), (CKA_SIGN, b_param) -> compare_bool a_param b_param
      | (CKA_SIGN_RECOVER, a_param), (CKA_SIGN_RECOVER, b_param) -> compare_bool a_param b_param
      | (CKA_VERIFY, a_param), (CKA_VERIFY, b_param) -> compare_bool a_param b_param
      | (CKA_VERIFY_RECOVER, a_param), (CKA_VERIFY_RECOVER, b_param) -> compare_bool a_param b_param
      | (CKA_DERIVE, a_param), (CKA_DERIVE, b_param) -> compare_bool a_param b_param
      | (CKA_EXTRACTABLE, a_param), (CKA_EXTRACTABLE, b_param) -> compare_bool a_param b_param
      | (CKA_LOCAL, a_param), (CKA_LOCAL, b_param) -> compare_bool a_param b_param
      | (CKA_NEVER_EXTRACTABLE, a_param), (CKA_NEVER_EXTRACTABLE, b_param) -> compare_bool a_param b_param
      | (CKA_ALWAYS_SENSITIVE, a_param), (CKA_ALWAYS_SENSITIVE, b_param) -> compare_bool a_param b_param
      | (CKA_MODIFIABLE, a_param), (CKA_MODIFIABLE, b_param) -> compare_bool a_param b_param
      | (CKA_ALWAYS_AUTHENTICATE, a_param), (CKA_ALWAYS_AUTHENTICATE, b_param) -> compare_bool a_param b_param
      | (CKA_WRAP_WITH_TRUSTED, a_param), (CKA_WRAP_WITH_TRUSTED, b_param) -> compare_bool a_param b_param
      | (CKA_LABEL, a_param), (CKA_LABEL, b_param) -> compare_string a_param b_param
      | (CKA_VALUE, a_param), (CKA_VALUE, b_param) -> compare_string a_param b_param
      | (CKA_SUBJECT, a_param), (CKA_SUBJECT, b_param) -> compare_string a_param b_param
      | (CKA_ID, a_param), (CKA_ID, b_param) -> compare_string a_param b_param
      | (CKA_PRIME_BITS, a_param), (CKA_PRIME_BITS,  b_param) -> compare_ulong a_param b_param
      | (CKA_SUBPRIME_BITS, a_param), (CKA_SUBPRIME_BITS, b_param) -> compare_ulong a_param b_param
      | (CKA_CS_UNKNOWN a_ul, NOT_IMPLEMENTED a_param),
        (CKA_CS_UNKNOWN b_ul, NOT_IMPLEMENTED b_param) ->
          let cmp = Unsigned.ULong.compare a_ul b_ul in
          if cmp = 0
          then compare_string a_param b_param
          else cmp
        (* Should have been covered by the comparison of attribute types,
           or by the above cases. *)
      | (CKA_CLASS, _), _ -> assert false
      | (CKA_KEY_TYPE, _), _ -> assert false
      | (CKA_MODULUS_BITS, _), _ -> assert false
      | (CKA_VALUE_LEN, _), _ -> assert false
      | (CKA_KEY_GEN_MECHANISM, _), _ -> assert false
      | (CKA_TOKEN, _), _ -> assert false
      | (CKA_PRIVATE, _), _ -> assert false
      | (CKA_TRUSTED, _), _ -> assert false
      | (CKA_SENSITIVE, _), _ -> assert false
      | (CKA_ENCRYPT, _), _ -> assert false
      | (CKA_DECRYPT, _), _ -> assert false
      | (CKA_WRAP, _), _ -> assert false
      | (CKA_UNWRAP, _), _ -> assert false
      | (CKA_SIGN, _), _ -> assert false
      | (CKA_SIGN_RECOVER, _), _ -> assert false
      | (CKA_VERIFY, _), _ -> assert false
      | (CKA_VERIFY_RECOVER, _), _ -> assert false
      | (CKA_DERIVE, _), _ -> assert false
      | (CKA_EXTRACTABLE, _), _ -> assert false
      | (CKA_LOCAL, _), _ -> assert false
      | (CKA_NEVER_EXTRACTABLE, _), _ -> assert false
      | (CKA_ALWAYS_SENSITIVE, _), _ -> assert false
      | (CKA_MODIFIABLE, _), _ -> assert false
      | (CKA_ALWAYS_AUTHENTICATE, _), _ -> assert false
      | (CKA_WRAP_WITH_TRUSTED, _), _ -> assert false
      | (CKA_LABEL, _), _ -> assert false
      | (CKA_VALUE, _), _ -> assert false
      | (CKA_SUBJECT, _), _ -> assert false
      | (CKA_ID, _), _ -> assert false
      | (CKA_MODULUS, _), _ -> assert false
      | (CKA_PUBLIC_EXPONENT, _), _ -> assert false
      | (CKA_PRIVATE_EXPONENT, _), _ -> assert false
      | (CKA_PRIME_1, _), _ -> assert false
      | (CKA_PRIME_2, _), _ -> assert false
      | (CKA_EXPONENT_1, _), _ -> assert false
      | (CKA_EXPONENT_2, _), _ -> assert false
      | (CKA_COEFFICIENT, _), _ -> assert false
      | (CKA_PRIME, _), _ -> assert false
      | (CKA_SUBPRIME, _), _ -> assert false
      | (CKA_EC_PARAMS, _), _ -> assert false
      | (CKA_EC_POINT, _), _ -> assert false
      | (CKA_PRIME_BITS, _), _ -> assert false
      | (CKA_SUBPRIME_BITS, _), _ -> assert false
      | (CKA_CS_UNKNOWN _, _), _ -> assert false

let compare_pack (Pack a) (Pack b) = compare a b

let equal a b =
  compare a b = 0

let equal_pack (Pack a) (Pack b) = equal a b
