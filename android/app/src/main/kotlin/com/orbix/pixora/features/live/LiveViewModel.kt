package com.orbix.pixora.features.live

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

data class LiveUiState(
    val items: List<LiveWallpaper> = emptyList(),
    val loading: Boolean = true,
    val errorMsg: String? = null,
)

@HiltViewModel
class LiveViewModel @Inject constructor(
    private val repo: LiveWallpaperRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(LiveUiState())
    val state: StateFlow<LiveUiState> = _state.asStateFlow()

    init { refresh() }

    fun refresh() {
        viewModelScope.launch {
            _state.value = _state.value.copy(loading = _state.value.items.isEmpty(), errorMsg = null)
            val list = repo.fetchAll()
            _state.value = LiveUiState(
                items = list,
                loading = false,
                errorMsg = if (list.isEmpty()) "Sin live wallpapers (revisa conexión)" else null,
            )
        }
    }
}
