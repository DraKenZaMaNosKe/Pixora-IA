package com.orbix.pixora.features.wallpapers

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.orbix.pixora.data.models.Wallpaper
import com.orbix.pixora.data.repos.WallpaperRepository
import com.orbix.pixora.data.wallpaper.ApplyResult
import com.orbix.pixora.data.wallpaper.WallpaperApplyService
import dagger.hilt.android.lifecycle.HiltViewModel
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
    val errorMsg: String? = null,
    val event: DetailEvent? = null,
)

@HiltViewModel
class WallpaperDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repo: WallpaperRepository,
    private val applyService: WallpaperApplyService,
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

    fun apply() {
        val w = _state.value.wallpaper ?: return
        if (_state.value.applying) return
        viewModelScope.launch {
            _state.value = _state.value.copy(applying = true)
            val result = applyService.applyFromUrl(w.imageUrl)
            _state.value = _state.value.copy(
                applying = false,
                event = when (result) {
                    is ApplyResult.Success -> DetailEvent.Toast("Wallpaper aplicado ✨")
                    is ApplyResult.Error -> DetailEvent.Toast("Error: ${result.message}")
                },
            )
        }
    }

    fun consumeEvent() {
        _state.value = _state.value.copy(event = null)
    }
}
