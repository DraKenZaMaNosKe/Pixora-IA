package com.orbix.pixora.features.live

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.orbix.pixora.data.models.LiveWallpaper
import com.orbix.pixora.data.repos.LiveWallpaperRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class LiveDetailUiState(
    val wallpaper: LiveWallpaper? = null,
    val loading: Boolean = true,
    val errorMsg: String? = null,
)

@HiltViewModel
class LiveDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repo: LiveWallpaperRepository,
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
}
