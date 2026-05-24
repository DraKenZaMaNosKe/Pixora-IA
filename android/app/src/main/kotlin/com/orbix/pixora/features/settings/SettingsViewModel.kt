package com.orbix.pixora.features.settings

import androidx.lifecycle.ViewModel
import com.orbix.pixora.data.credits.CreditService
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    creditService: CreditService,
) : ViewModel() {
    val balance: Flow<Long> = creditService.balance
}
