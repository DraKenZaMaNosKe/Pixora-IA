package com.orbix.pixora.data.auth

import android.app.Activity
import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialException
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Local user record stored after a successful Google Sign-In.
 *
 * No backend syncs this yet — favorites and credits stay device-local.
 * When we wire Supabase Auth or a custom user table, this becomes the
 * source of identity for cross-device sync.
 */
data class PixoraUser(
    val sub: String,
    val name: String?,
    val email: String?,
    val photoUrl: String?,
)

private val Context.authDataStore by preferencesDataStore("pixora_auth")
private object AuthKeys {
    val SUB: Preferences.Key<String> = stringPreferencesKey("sub")
    val NAME: Preferences.Key<String> = stringPreferencesKey("name")
    val EMAIL: Preferences.Key<String> = stringPreferencesKey("email")
    val PHOTO: Preferences.Key<String> = stringPreferencesKey("photo")
}

/**
 * Pixora auth service — Credential Manager + Google ID token.
 *
 * Why Credential Manager: the legacy GoogleSignIn API is deprecated;
 * Credential Manager is Google's blessed replacement and integrates
 * with Passkeys later when we want it.
 *
 * Flow:
 *   1. Caller (PixoraAppBar avatar tap) → signIn(activity)
 *   2. We request a GoogleIdOption with our v1 Web Client ID
 *   3. The system shows the Google one-tap or full picker
 *   4. On success: parse the GoogleIdTokenCredential, persist to
 *      DataStore, emit on the user flow.
 *   5. signOut() clears DataStore and the flow.
 *
 * No backend call. Just identity capture + local persistence so
 * favorites/credits/etc. can later be uploaded keyed by sub.
 */
@Singleton
class AuthService @Inject constructor(
    @ApplicationContext private val context: Context,
) {

    // Type=3 (Web Client) from android/app/google-services.json — same
    // client v1 uses for Sign-In. Server-side this is configured in the
    // Pixora Firebase project (device-streaming-bab2df46).
    private val webClientId = "615188090674-gu1js8k59si00dioi22itasgrugdsgtt.apps.googleusercontent.com"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val cm = CredentialManager.create(context)

    private val _user = MutableStateFlow<PixoraUser?>(null)
    val user: StateFlow<PixoraUser?> = _user.asStateFlow()

    init {
        // Hydrate the cached user from DataStore on creation
        scope.launch {
            val prefs = context.authDataStore.data.first()
            val sub = prefs[AuthKeys.SUB] ?: return@launch
            _user.value = PixoraUser(
                sub = sub,
                name = prefs[AuthKeys.NAME],
                email = prefs[AuthKeys.EMAIL],
                photoUrl = prefs[AuthKeys.PHOTO],
            )
        }
    }

    /**
     * Trigger the Credential Manager sign-in UX. Suspending — caller
     * should be in a coroutine scope (ViewModel.viewModelScope is fine).
     */
    suspend fun signIn(activity: Activity): SignInResult {
        return runCatching {
            val option = GetGoogleIdOption.Builder()
                .setServerClientId(webClientId)
                .setFilterByAuthorizedAccounts(false) // show all accounts first time
                .setAutoSelectEnabled(true)
                .build()
            val request = GetCredentialRequest.Builder()
                .addCredentialOption(option)
                .build()
            val response = cm.getCredential(context = activity, request = request)
            val credential = response.credential
            if (credential is CustomCredential &&
                credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
            ) {
                val gIdToken = GoogleIdTokenCredential.createFrom(credential.data)
                val user = PixoraUser(
                    sub = gIdToken.id,
                    name = gIdToken.displayName,
                    email = gIdToken.id,
                    photoUrl = gIdToken.profilePictureUri?.toString(),
                )
                persist(user)
                _user.value = user
                SignInResult.Success(user)
            } else {
                SignInResult.Error("Credencial inesperada")
            }
        }.getOrElse { e ->
            when (e) {
                is GetCredentialException -> SignInResult.Cancelled(e.message ?: "cancelado")
                is GoogleIdTokenParsingException -> SignInResult.Error("Token inválido")
                else -> SignInResult.Error(e.message ?: "Error desconocido")
            }
        }
    }

    fun signOut() {
        scope.launch {
            context.authDataStore.edit { it.clear() }
            _user.value = null
        }
    }

    private suspend fun persist(user: PixoraUser) {
        context.authDataStore.edit { prefs ->
            prefs[AuthKeys.SUB] = user.sub
            user.name?.let { prefs[AuthKeys.NAME] = it }
            user.email?.let { prefs[AuthKeys.EMAIL] = it }
            user.photoUrl?.let { prefs[AuthKeys.PHOTO] = it }
        }
    }
}

sealed class SignInResult {
    data class Success(val user: PixoraUser) : SignInResult()
    data class Cancelled(val reason: String) : SignInResult()
    data class Error(val message: String) : SignInResult()
}
