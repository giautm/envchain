#pragma once

#include <libsecret/secret.h>

// Swift 6 cannot call variadic C functions directly.
// These shims provide non-variadic wrappers for the specific calling patterns used.

static inline gboolean
envchain_secret_password_store(const SecretSchema *schema,
                               const gchar *collection,
                               const gchar *label,
                               const gchar *password,
                               GError **error,
                               const gchar *service_val,
                               const gchar *account_val) {
  return secret_password_store_sync(schema, collection,
    label, password, NULL, error, "service", service_val,
    "account", account_val, NULL);
}

static inline GList *
envchain_secret_password_search(const SecretSchema *schema,
                                SecretSearchFlags flags,
                                GError **error,
                                const gchar *service_val) {
  return secret_password_search_sync(schema, flags,
    NULL, error, "service", service_val, NULL);
}

static inline GList *
envchain_secret_password_search_all(const SecretSchema *schema,
                                    SecretSearchFlags flags,
                                    GError **error) {
  return secret_password_search_sync(schema, flags, NULL, error, NULL);
}

static inline gboolean
envchain_secret_password_clear(const SecretSchema *schema,
                               GError **error,
                               const gchar *service_val,
                               const gchar *account_val) {
  return secret_password_clear_sync(schema, NULL, error,
    "service", service_val, "account", account_val, NULL);
}
