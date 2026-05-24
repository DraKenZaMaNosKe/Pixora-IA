package com.orbix.pixora.features.wallpapers

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.orbix.pixora.data.models.Wallpaper
import com.orbix.pixora.data.repos.WallpaperRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * State surfaced to the WallpapersScreen.
 *
 * `loading` is only true on the first fetch — once we have data, refresh
 * happens silently in the background to avoid flashing the user.
 */
data class WallpapersUiState(
    val wallpapers: List<Wallpaper> = emptyList(),
    val loading: Boolean = true,
    val errorMsg: String? = null,
)

@HiltViewModel
class WallpapersViewModel @Inject constructor(
    private val repo: WallpaperRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(WallpapersUiState())
    val state: StateFlow<WallpapersUiState> = _state.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            // Don't blank existing list while refreshing — just hint loading.
            _state.value = _state.value.copy(
                loading = _state.value.wallpapers.isEmpty(),
                errorMsg = null,
            )
            val list = repo.fetchAll()
            _state.value = WallpapersUiState(
                wallpapers = list,
                loading = false,
                errorMsg = if (list.isEmpty()) "Sin wallpapers (revisa conexión)" else null,
            )
        }
    }
}
