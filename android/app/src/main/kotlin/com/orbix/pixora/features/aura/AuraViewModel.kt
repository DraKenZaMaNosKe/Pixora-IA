package com.orbix.pixora.features.aura

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.orbix.pixora.data.models.AuraTrack
import com.orbix.pixora.data.repos.AuraRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class AuraUiState(
    val tracks: List<AuraTrack> = emptyList(),
    val loading: Boolean = true,
    val errorMsg: String? = null,
) {
    val frequencies: List<AuraTrack> get() = tracks.filter { it.category == "frequency" }
    val nature: List<AuraTrack> get() = tracks.filter { it.category == "nature" }
    val other: List<AuraTrack> get() =
        tracks.filter { it.category !in listOf("frequency", "nature") }
}

@HiltViewModel
class AuraViewModel @Inject constructor(
    private val repo: AuraRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(AuraUiState())
    val state: StateFlow<AuraUiState> = _state.asStateFlow()

    init { refresh() }

    fun refresh() {
        viewModelScope.launch {
            _state.value = _state.value.copy(
                loading = _state.value.tracks.isEmpty(),
                errorMsg = null,
            )
            val list = repo.fetchAll()
            _state.value = AuraUiState(
                tracks = list,
                loading = false,
                errorMsg = if (list.isEmpty()) "Sin tracks AURA (revisa conexión)" else null,
            )
        }
    }
}
