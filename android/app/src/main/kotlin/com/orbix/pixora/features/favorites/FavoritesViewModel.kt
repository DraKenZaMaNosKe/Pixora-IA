package com.orbix.pixora.features.favorites

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.orbix.pixora.data.db.FavoriteEntity
import com.orbix.pixora.data.favorites.FavoriteService
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class FavoritesViewModel @Inject constructor(
    private val service: FavoriteService,
) : ViewModel() {
    val items: Flow<List<FavoriteEntity>> = service.observeAll()

    fun remove(id: String) {
        viewModelScope.launch { service.remove(id) }
    }
}
