package com.irannavigator.demo

import android.content.Context
import android.speech.tts.TextToSpeech
import java.util.Locale

class PersianVoice(
    context: Context,
    private val onReady: (Boolean, String) -> Unit
) : TextToSpeech.OnInitListener {
    private var engine: TextToSpeech? = TextToSpeech(context.applicationContext, this)
    var isReady: Boolean = false
        private set

    override fun onInit(status: Int) {
        val tts = engine
        if (status != TextToSpeech.SUCCESS || tts == null) {
            isReady = false
            onReady(false, "موتور گفتار در دسترس نیست")
            return
        }

        val persian = Locale("fa", "IR")
        val availability = tts.isLanguageAvailable(persian)
        if (availability < TextToSpeech.LANG_AVAILABLE) {
            isReady = false
            onReady(false, "صدای فارسی روی گوشی نصب نیست")
            return
        }

        val result = tts.setLanguage(persian)
        if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
            isReady = false
            onReady(false, "زبان فارسی توسط موتور گفتار پشتیبانی نمی‌شود")
            return
        }

        tts.setSpeechRate(0.96f)
        tts.setPitch(1.0f)
        isReady = true
        onReady(true, "راهنمای صوتی فارسی آماده است")
    }

    fun speak(text: String) {
        if (!isReady || text.isBlank()) return
        engine?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "iran-nav-${System.currentTimeMillis()}")
    }

    fun stop() {
        engine?.stop()
    }

    fun shutdown() {
        engine?.stop()
        engine?.shutdown()
        engine = null
        isReady = false
    }
}
