package com.orbix.pixora.features.wallpapers

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.orbix.pixora.data.models.Wallpaper
import com.orbix.pixora.data.repos.WallpaperRepository
import android.app.Activity
import com.orbix.pixora.data.ads.AdService
import com.orbix.pixora.data.credits.CreditService
import com.orbix.pixora.data.wallpaper.ApplyResult
import com.orbix.pixora.data.wallpaper.WallpaperApplyService
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/** UI events that surface as one-shot messages (snackbars). */
sealed class DetailEvent {
    data class Toast(val message: String) : DetailEvent()
}

data class WallpaperDetailUiState(
    val wallpaper: Wallpaper? = null,
    val loading: Boolean = true,
    val applying: Boolean = false,
    /** True for ~2s after a successful apply so the CTA can show feedback. */
    val justApplied: Boolean = false,
    val errorMsg: String? = null,
    val event: DetailEvent? = null,
)

@HiltViewModel
class WallpaperDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repo: WallpaperRepository,
    private val applyService: WallpaperApplyService,
    private val adService: AdService,
    private val creditService: CreditService,
) : ViewModel() {

    private val wallpaperId: String = savedStateHandle.get<String>("id").orEmpty()

    private val _state = MutableStateFlow(WallpaperDetailUiState())
    val state: StateFlow<WallpaperDetailUiState> = _state.asStateFlow()

    init {
        load()
    }

    private fun load() {
        viewModelScope.launch {
            val w = repo.fetchById(wallpaperId)
            _state.value = _state.value.copy(
                wallpaper = w,
                loading = false,
                errorMsg = if (w == null) "Wallpaper no encontrado" else null,
            )
        }
    }

    fun apply(activity: Activity) {
        val w = _state.value.wallpaper ?: return
        if (_state.value.applying) return
        adService.showInterstitial(activity) { awardedCredit ->
            viewModelScope.launch {
                _state.value = _state.value.copy(applying = true, justApplied = false)
                val result = applyService.applyFromUrl(w.imageUrl, isPanoramic = w.isPanoramic)
                when (result) {
                    is ApplyResult.Success -> {
                        if (awardedCredit) creditService.earnFromAd()
                        _state.value = _state.value.copy(
                            applying = false,
                            justApplied = true,
                            event = DetailEvent.Toast(
                                if (awardedCredit) "Aplicado ✨ +1 💎" else "Wallpaper aplicado ✨",
                            ),
                        )
                        delay(2500)
                        _state.value = _state.value.copy(justApplied = false)
                    }
                    is ApplyResult.Error -> {
                        _state.value = _state.value.copy(
                            applying = false,
                            event = DetailEvent.Toast("Error: ${result.message}"),
                        )
                    }
                }
            }
        }
    }

    fun consumeEvent() {
        _state.value = _state.value.copy(event = null)
    }
}
