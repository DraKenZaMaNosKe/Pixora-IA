package com.orbix.pixora.features.live

import android.app.Activity
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.orbix.pixora.data.ads.AdService
import com.orbix.pixora.data.credits.CreditService
import com.orbix.pixora.data.models.LiveWallpaper
import com.orbix.pixora.data.repos.LiveWallpaperRepository
import com.orbix.pixora.data.wallpaper.LiveApplyResult
import com.orbix.pixora.data.wallpaper.LiveApplyService
import com.orbix.pixora.ui.components.DownloadStage
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class LiveDetailUiState(
    val wallpaper: LiveWallpaper? = null,
    val loading: Boolean = true,
    val errorMsg: String? = null,
    val downloadStage: DownloadStage = DownloadStage.Idle,
    val downloadError: String? = null,
    val toast: String? = null,
)

@HiltViewModel
class LiveDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repo: LiveWallpaperRepository,
    private val applyService: LiveApplyService,
    private val adService: AdService,
    private val creditService: CreditService,
) : ViewModel() {

    private val wallpaperId: String = savedStateHandle.get<String>("id").orEmpty()

    private val _state = MutableStateFlow(LiveDetailUiState())
    val state: StateFlow<LiveDetailUiState> = _state.asStateFlow()

    init { load() }

    private fun load() {
        viewModelScope.launch {
            val all = repo.fetchAll()
            val w = all.firstOrNull { it.id == wallpaperId }
            _state.value = LiveDetailUiState(
                wallpaper = w,
                loading = false,
                errorMsg = if (w == null) "Live wallpaper no encontrado" else null,
            )
        }
    }

    fun apply(activity: Activity) {
        val w = _state.value.wallpaper ?: return
        if (_state.value.downloadStage != DownloadStage.Idle) return
        adService.showInterstitial(activity) { awardedCredit ->
            viewModelScope.launch {
                _state.value = _state.value.copy(
                    downloadStage = DownloadStage.Downloading,
                    downloadError = null,
                )
                val result = applyService.stageAndLaunch(w.videoUrl, activity)
                when (result) {
                    is LiveApplyResult.PickerLaunched -> {
                        if (awardedCredit) creditService.earnFromAd()
                        _state.value = _state.value.copy(
                            downloadStage = DownloadStage.Success,
                            toast = if (awardedCredit) "Listo ✨ +1 💎 · Confirma en el picker" else "Listo · Confirma en el picker",
                        )
                        delay(1500)
                        _state.value = _state.value.copy(downloadStage = DownloadStage.Idle)
                    }
                    is LiveApplyResult.Error -> {
                        _state.value = _state.value.copy(
                            downloadStage = DownloadStage.Error,
                            downloadError = result.message,
                            toast = "Error: ${result.message}",
                        )
                        delay(3000)
                        _state.value = _state.value.copy(
                            downloadStage = DownloadStage.Idle,
                            downloadError = null,
                        )
                    }
                }
            }
        }
    }

    fun consumeToast() {
        _state.value = _state.value.copy(toast = null)
    }
}
