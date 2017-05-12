(** Mechanisms (type and value) ([CK_KEY_TYPE]) *)
type _t
type t = _t Ctypes.structure

type u =
  | CKM_SHA_1
  | CKM_SHA224
  | CKM_SHA256
  | CKM_SHA512
  | CKM_MD5
  | CKM_RSA_PKCS_KEY_PAIR_GEN
  | CKM_RSA_X9_31_KEY_PAIR_GEN
  | CKM_RSA_PKCS
  | CKM_RSA_PKCS_OAEP of P11_rsa_pkcs_oaep_params.t
  | CKM_RSA_X_509
  | CKM_RSA_PKCS_PSS of P11_rsa_pkcs_pss_params.t
  | CKM_SHA1_RSA_PKCS
  | CKM_SHA224_RSA_PKCS
  | CKM_SHA256_RSA_PKCS
  | CKM_SHA384_RSA_PKCS
  | CKM_SHA512_RSA_PKCS
  | CKM_SHA1_RSA_PKCS_PSS of P11_rsa_pkcs_pss_params.t
  | CKM_SHA224_RSA_PKCS_PSS of P11_rsa_pkcs_pss_params.t
  | CKM_SHA256_RSA_PKCS_PSS of P11_rsa_pkcs_pss_params.t
  | CKM_SHA384_RSA_PKCS_PSS of P11_rsa_pkcs_pss_params.t
  | CKM_SHA512_RSA_PKCS_PSS of P11_rsa_pkcs_pss_params.t
  | CKM_AES_KEY_GEN
  | CKM_AES_ECB
  | CKM_AES_CBC of string
  | CKM_AES_CBC_PAD of string
  | CKM_AES_MAC
  | CKM_AES_MAC_GENERAL of Pkcs11_CK_ULONG.t
  | CKM_AES_ECB_ENCRYPT_DATA of Pkcs11_CK_KEY_DERIVATION_STRING_DATA.u
  | CKM_AES_CBC_ENCRYPT_DATA of P11_aes_cbc_encrypt_data_params.t
  | CKM_DES_KEY_GEN
  | CKM_DES_ECB
  | CKM_DES_CBC of string
  | CKM_DES_CBC_PAD of string
  | CKM_DES_MAC
  | CKM_DES_MAC_GENERAL of Pkcs11_CK_ULONG.t
  | CKM_DES_ECB_ENCRYPT_DATA of Pkcs11_CK_KEY_DERIVATION_STRING_DATA.u
  | CKM_DES_CBC_ENCRYPT_DATA of P11_des_cbc_encrypt_data_params.t
  | CKM_DES3_KEY_GEN
  | CKM_DES3_ECB
  | CKM_DES3_CBC of string
  | CKM_DES3_CBC_PAD of string
  | CKM_DES3_MAC
  | CKM_DES3_MAC_GENERAL of Pkcs11_CK_ULONG.t
  | CKM_DES3_ECB_ENCRYPT_DATA of Pkcs11_CK_KEY_DERIVATION_STRING_DATA.u
  | CKM_DES3_CBC_ENCRYPT_DATA of P11_des_cbc_encrypt_data_params.t
  | CKM_CONCATENATE_BASE_AND_DATA of Pkcs11_CK_KEY_DERIVATION_STRING_DATA.u
  | CKM_CONCATENATE_DATA_AND_BASE of Pkcs11_CK_KEY_DERIVATION_STRING_DATA.u
  | CKM_XOR_BASE_AND_DATA of Pkcs11_CK_KEY_DERIVATION_STRING_DATA.u
  | CKM_EXTRACT_KEY_FROM_KEY of Pkcs11_CK_ULONG.t
  | CKM_CONCATENATE_BASE_AND_KEY of Pkcs11_CK_OBJECT_HANDLE.t
  | CKM_EC_KEY_PAIR_GEN
  | CKM_ECDSA
  | CKM_ECDSA_SHA1
  | CKM_ECDH1_DERIVE of Pkcs11_CK_ECDH1_DERIVE_PARAMS.u
  | CKM_ECDH1_COFACTOR_DERIVE of Pkcs11_CK_ECDH1_DERIVE_PARAMS.u
  | CKM_ECMQV_DERIVE of Pkcs11_CK_ECMQV_DERIVE_PARAMS.u
  | CKM_PKCS5_PBKD2 of P11_pkcs5_pbkd2_data_params.t
  | CKM_CS_UNKNOWN of P11_raw_payload_params.t

val mechanism_type: u -> P11_mechanism_type.t

val make : u -> t
val view : t -> u

val compare: u -> u -> int

val ck_mechanism : t Ctypes.typ
