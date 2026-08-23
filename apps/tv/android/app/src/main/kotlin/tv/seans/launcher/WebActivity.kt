package tv.seans.launcher

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout

/**
 * A web page, full screen, driven by the remote.
 *
 * An Activity of its own rather than a WebView inside Flutter, and that is the
 * whole point: embedded as a platform view, arrow keys never reach the page —
 * Flutter's focus traversal takes them first and moves focus around the Dart
 * widget tree instead. A plain WebView in its own window gets the key events
 * the way any browser does, and its own spatial navigation works.
 *
 * It also means gamepad buttons and fullscreen video behave, which is the
 * difference between a page that loads and a page that can be used.
 */
class WebActivity : Activity() {

    private var webView: WebView? = null

    /** Where a video goes when the page asks for the whole screen. */
    private var fullscreen: View? = null
    private var onFullscreenExit: WebChromeClient.CustomViewCallback? = null

    private lateinit var root: FrameLayout

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val url = intent.getStringExtra(EXTRA_URL) ?: run { finish(); return }
        val agent = intent.getStringExtra(EXTRA_AGENT)

        root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        setContentView(root)

        val view = WebView(this).apply {
            setBackgroundColor(Color.BLACK)
            // Without this the view never takes focus from the remote, and the
            // page's own arrow-key navigation never starts.
            isFocusable = true
            isFocusableInTouchMode = true

            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.loadWithOverviewMode = true
            settings.useWideViewPort = true
            if (agent != null) settings.userAgentString = agent

            webViewClient = WebViewClient()
            webChromeClient = FullscreenChrome()
        }

        root.addView(
            view,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        webView = view
        view.requestFocus()
        view.loadUrl(url)
    }

    /** BACK walks the page's history first, the way it does in a browser. */
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (fullscreen != null) {
            onFullscreenExit?.onCustomViewHidden()
            return
        }

        val view = webView
        if (view != null && view.canGoBack()) {
            view.goBack()
            return
        }

        @Suppress("DEPRECATION")
        super.onBackPressed()
    }

    override fun onDestroy() {
        webView?.let {
            root.removeView(it)
            it.destroy()
        }
        webView = null
        super.onDestroy()
    }

    /** Lets a video take the whole window and give it back. */
    private inner class FullscreenChrome : WebChromeClient() {
        override fun onShowCustomView(
            view: View,
            callback: CustomViewCallback,
        ) {
            if (fullscreen != null) {
                callback.onCustomViewHidden()
                return
            }

            fullscreen = view
            onFullscreenExit = callback
            root.addView(
                view,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
            view.requestFocus()
        }

        override fun onHideCustomView() {
            fullscreen?.let { root.removeView(it) }
            fullscreen = null
            onFullscreenExit = null
            webView?.requestFocus()
        }
    }

    companion object {
        private const val EXTRA_URL = "url"
        private const val EXTRA_AGENT = "agent"

        fun intent(context: Context, url: String, agent: String?): Intent =
            Intent(context, WebActivity::class.java)
                .putExtra(EXTRA_URL, url)
                .putExtra(EXTRA_AGENT, agent)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
}
