package com.orbix.pixora.features.wallpapers

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.orbix.pixora.data.db.FavoriteEntity
import com.orbix.pixora.data.favorites.FavoriteService
import com.orbix.pixora.data.models.Wallpaper
import com.orbix.pixora.data.repos.WallpaperRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

data class WallpapersUiState(
    val wallpapers: List<Wallpaper> = emptyList(),
    val loading: Boolean = true,
    val errorMsg: String? = null,
)

@HiltViewModel
class WallpapersViewModel @Inject constructor(
    private val repo: WallpaperRepository,
    private val favorites: FavoriteService,
) : ViewModel() {

    private val _state = MutableStateFlow(WallpapersUiState())
    val state: StateFlow<WallpapersUiState> = _state.asStateFlow()

    /** All favorited wallpaper IDs — used to decorate cards with the heart. */
    val favoriteIds: StateFlow<Set<String>> = favorites.observeAll()
        .map { list -> list.filter { it.kind == FavoriteEntity.KIND_WALLPAPER }.map { it.id }.toSet() }
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptySet())

    init { refresh() }

    fun refresh() {
        viewModelScope.launch {
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

    fun toggleFavorite(w: Wallpaper) {
        viewModelScope.launch {
            favorites.toggle(
                id = w.id,
                kind = FavoriteEntity.KIND_WALLPAPER,
                name = w.name,
                previewUrl = w.previewUrl,
                accentHex = w.glowColor,
            )
        }
    }
}
