package com.shehzad.finance_tracker

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

/** Writes backups into a folder the user picked, through Android's storage
 *  access framework, so the files stay when the app is uninstalled. Only
 *  files this app named are ever deleted from that folder. */
class BackupFolder(private val activity: Activity) {

    companion object {
        const val PICK_REQUEST = 4711
        private const val PREFIX = "finance-tracker-auto-"
        private const val SUFFIX = ".json"
    }

    private var pending: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())
    private val resolver get() = activity.contentResolver
    private val access = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pick" -> pick(result)
            "write" -> {
                val uri = call.argument<String>("uri")
                val name = call.argument<String>("name")
                val text = call.argument<String>("text")
                val keep = call.argument<Int>("keep") ?: 4
                if (uri == null || name == null || text == null || !name.startsWith(PREFIX) || !name.endsWith(SUFFIX)) {
                    result.error("bad_args", "uri, name and text are needed", null)
                    return
                }
                Thread {
                    try {
                        val written = write(Uri.parse(uri), name, text, keep)
                        main.post { result.success(written) }
                    } catch (e: Exception) {
                        main.post { result.error("write_failed", e.message, null) }
                    }
                }.start()
            }
            "hasAccess" -> result.success(call.argument<String>("uri")?.let { hasAccess(Uri.parse(it)) } ?: false)
            "release" -> {
                call.argument<String>("uri")?.let { release(Uri.parse(it)) }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun pick(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "A folder is already being chosen", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            .addFlags(access or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        pending = result
        try {
            activity.startActivityForResult(intent, PICK_REQUEST)
        } catch (e: ActivityNotFoundException) {
            pending = null
            result.error("no_picker", "This phone has no folder picker", null)
        }
    }

    /** Called from the activity; returns true when the result was ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_REQUEST) return false
        val result = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        try {
            resolver.takePersistableUriPermission(uri, access)
            result.success(mapOf("uri" to uri.toString(), "name" to (displayName(uri) ?: "the chosen folder")))
        } catch (e: SecurityException) {
            result.error("no_access", e.message, null)
        }
        return true
    }

    private fun folderDocument(tree: Uri): Uri =
        DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))

    private fun displayName(tree: Uri): String? = try {
        resolver.query(folderDocument(tree), arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null }
    } catch (e: Exception) {
        null
    }

    private fun hasAccess(tree: Uri): Boolean =
        resolver.persistedUriPermissions.any { it.uri == tree && it.isWritePermission }

    private fun release(tree: Uri) {
        try {
            resolver.releasePersistableUriPermission(tree, access)
        } catch (e: SecurityException) {
            // Already gone.
        }
    }

    /** Writes one backup, then deletes this app's older ones beyond [keep].
     *  Returns the file's name as the folder shows it. */
    private fun write(tree: Uri, name: String, text: String, keep: Int): String {
        val doc = DocumentsContract.createDocument(resolver, folderDocument(tree), "application/json", name)
            ?: throw IOException("The folder refused a new file")
        try {
            val out = resolver.openOutputStream(doc, "wt") ?: throw IOException("The file couldn't be opened")
            out.use { it.write(text.toByteArray(Charsets.UTF_8)) }
        } catch (e: Exception) {
            try {
                DocumentsContract.deleteDocument(resolver, doc)
            } catch (ignored: Exception) {
            }
            throw e
        }
        prune(tree, keep)
        return displayNameOf(doc) ?: name
    }

    private fun displayNameOf(doc: Uri): String? = try {
        resolver.query(doc, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null }
    } catch (e: Exception) {
        null
    }

    private fun prune(tree: Uri, keep: Int) {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val ours = mutableListOf<Pair<String, String>>()
        try {
            resolver.query(
                children,
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null, null, null,
            )?.use {
                while (it.moveToNext()) {
                    val name = it.getString(1) ?: continue
                    if (name.startsWith(PREFIX) && name.endsWith(SUFFIX)) ours.add(it.getString(0) to name)
                }
            }
        } catch (e: Exception) {
            return
        }
        // Names carry the date and time, so newest sorts last.
        ours.sortedByDescending { it.second }.drop(keep).forEach { (id, _) ->
            try {
                DocumentsContract.deleteDocument(resolver, DocumentsContract.buildDocumentUriUsingTree(tree, id))
            } catch (e: Exception) {
                // Leave a file that can't be deleted; the next backup tries again.
            }
        }
    }
}
