#include "cert-openssl.h"

#include <gio/gio.h>
#include <openssl/bn.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/rand.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>

static void
set_openssl_error (GError **error, const char *prefix)
{
  char buf[256];

  ERR_error_string_n (ERR_get_error (), buf, sizeof buf);
  g_set_error (error, G_IO_ERROR, G_IO_ERROR_FAILED, "%s: %s", prefix, buf);
}

gboolean
ocrpc_cert_create_pem_files (const gchar *cert_path,
                             const gchar *key_path,
                             const gchar *cn,
                             gboolean server_san,
                             const gchar *ca_pem_path,
                             const gchar *ca_key_path,
                             GError **error)
{
  EVP_PKEY *pkey = NULL;
  X509 *crt = NULL;
  X509 *ca_crt = NULL;
  EVP_PKEY *ca_key = NULL;
  BIO *bio = NULL;
  unsigned char serial[16];
  BIGNUM *bn = NULL;
  gboolean ok = FALSE;
  gboolean use_ca;

  pkey = EVP_RSA_gen (2048);
  if (pkey == NULL)
    {
      set_openssl_error (error, "privkey_generate");
      goto out;
    }

  crt = X509_new ();
  if (crt == NULL)
    {
      set_openssl_error (error, "set_version");
      goto out;
    }
  if (X509_set_version (crt, X509_VERSION_3) != 1)
    {
      set_openssl_error (error, "set_version");
      goto out;
    }
  if (X509_NAME_add_entry_by_txt (X509_get_subject_name (crt), "CN",
                                  MBSTRING_ASC, (const unsigned char *) cn,
                                  -1, -1, 0)
      != 1)
    {
      set_openssl_error (error, "set_dn_by_oid");
      goto out;
    }
  if (RAND_bytes (serial, (int) sizeof serial) != 1)
    {
      set_openssl_error (error, "set_serial");
      goto out;
    }
  bn = BN_bin2bn (serial, (int) sizeof serial, NULL);
  if (bn == NULL || BN_to_ASN1_INTEGER (bn, X509_get_serialNumber (crt)) == NULL)
    {
      set_openssl_error (error, "set_serial");
      goto out;
    }
  if (X509_gmtime_adj (X509_getm_notBefore (crt), 0) == NULL
      || X509_gmtime_adj (X509_getm_notAfter (crt),
                          3650 * 24 * 60 * 60)
             == NULL)
    {
      set_openssl_error (error, "set_activation_time");
      goto out;
    }
  if (X509_set_pubkey (crt, pkey) != 1)
    {
      set_openssl_error (error, "set_key");
      goto out;
    }
  if (server_san)
    {
      GENERAL_NAMES *gens = sk_GENERAL_NAME_new_null ();
      GENERAL_NAME *gen = GENERAL_NAME_new ();
      ASN1_IA5STRING *ia5 = ASN1_IA5STRING_new ();

      if (gens == NULL || gen == NULL || ia5 == NULL
          || ASN1_STRING_set (ia5, "localhost", -1) != 1)
        {
          GENERAL_NAME_free (gen);
          ASN1_IA5STRING_free (ia5);
          GENERAL_NAMES_free (gens);
          set_openssl_error (error, "SAN DNS");
          goto out;
        }
      GENERAL_NAME_set0_value (gen, GEN_DNS, ia5);
      sk_GENERAL_NAME_push (gens, gen);
      if (X509_add1_ext_i2d (crt, NID_subject_alt_name, gens, 0, 0) <= 0)
        {
          GENERAL_NAMES_free (gens);
          set_openssl_error (error, "SAN DNS");
          goto out;
        }
      GENERAL_NAMES_free (gens);
    }

  use_ca = ca_pem_path != NULL && ca_pem_path[0] != '\0'
           && ca_key_path != NULL && ca_key_path[0] != '\0';
  if (use_ca)
    {
      bio = BIO_new_file (ca_pem_path, "r");
      if (bio == NULL)
        {
          set_openssl_error (error, "ca import");
          goto out;
        }
      ca_crt = PEM_read_bio_X509 (bio, NULL, NULL, NULL);
      BIO_free (bio);
      bio = NULL;
      if (ca_crt == NULL)
        {
          set_openssl_error (error, "ca import");
          goto out;
        }
      bio = BIO_new_file (ca_key_path, "r");
      if (bio == NULL)
        {
          set_openssl_error (error, "ca key import");
          goto out;
        }
      ca_key = PEM_read_bio_PrivateKey (bio, NULL, NULL, NULL);
      BIO_free (bio);
      bio = NULL;
      if (ca_key == NULL)
        {
          set_openssl_error (error, "ca key import");
          goto out;
        }
      if (X509_set_issuer_name (crt, X509_get_subject_name (ca_crt)) != 1
          || X509_sign (crt, ca_key, EVP_sha256 ()) == 0)
        {
          set_openssl_error (error, "sign2");
          goto out;
        }
    }
  else if (X509_set_issuer_name (crt, X509_get_subject_name (crt)) != 1
           || X509_sign (crt, pkey, EVP_sha256 ()) == 0)
    {
      set_openssl_error (error, "sign2");
      goto out;
    }

  bio = BIO_new_file (key_path, "w");
  if (bio == NULL || PEM_write_bio_PrivateKey (bio, pkey, NULL, NULL, 0,
                                               NULL, NULL)
                         != 1)
    {
      set_openssl_error (error, "privkey_export");
      goto out;
    }
  BIO_free (bio);
  bio = BIO_new_file (cert_path, "w");
  if (bio == NULL || PEM_write_bio_X509 (bio, crt) != 1)
    {
      set_openssl_error (error, "crt_export");
      goto out;
    }
  ok = TRUE;

out:
  BIO_free (bio);
  BN_free (bn);
  X509_free (ca_crt);
  EVP_PKEY_free (ca_key);
  X509_free (crt);
  EVP_PKEY_free (pkey);
  return ok;
}
