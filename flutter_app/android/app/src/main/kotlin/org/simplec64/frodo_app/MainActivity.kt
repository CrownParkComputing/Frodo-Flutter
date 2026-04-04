package org.simplec64.frodo_app

import android.os.Bundle
import android.util.Log
import android.view.InputDevice
import android.view.KeyCharacterMap
import android.view.KeyEvent
import android.view.MotionEvent
import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.libsdl.app.SDL
import org.apache.commons.compress.archivers.sevenz.SevenZFile
import java.io.File
import org.libsdl.app.SDLControllerManager

class MainActivity : FlutterActivity() {
	companion object {
		private const val TAG = "MainActivity"
		private const val ARCHIVE_AUTH_CHANNEL = "archive_auth"
		private const val ARCHIVE_EXTRACT_CHANNEL = "archive_extract"
		private const val GAMEPAD_CHANNEL = "gamepad_input"
		private const val GAMEPAD_EVENTS_CHANNEL = "gamepad_events"
		private val SUPPORTED_EXTENSIONS = setOf(".d64", ".t64", ".tap", ".z64", ".prg")

		init {
			System.loadLibrary("SDL2")
		}
	}

	// EventChannel sink — set when Flutter side is listening
	private var gamepadEventSink: EventChannel.EventSink? = null

	private fun isGamepadDevice(deviceId: Int): Boolean {
		val d = InputDevice.getDevice(deviceId) ?: return false
		val sources = d.sources
		val fromSource =
			(sources and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD ||
			(sources and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK ||
			(sources and InputDevice.SOURCE_DPAD) == InputDevice.SOURCE_DPAD
		return fromSource || SDLControllerManager.isDeviceSDLJoystick(deviceId)
	}

	private fun isLikelyGamepadKey(keyCode: Int): Boolean {
		return when (keyCode) {
			KeyEvent.KEYCODE_DPAD_UP,
			KeyEvent.KEYCODE_DPAD_DOWN,
			KeyEvent.KEYCODE_DPAD_LEFT,
			KeyEvent.KEYCODE_DPAD_RIGHT,
			KeyEvent.KEYCODE_DPAD_CENTER,
			KeyEvent.KEYCODE_BUTTON_A,
			KeyEvent.KEYCODE_BUTTON_B,
			KeyEvent.KEYCODE_BUTTON_C,
			KeyEvent.KEYCODE_BUTTON_X,
			KeyEvent.KEYCODE_BUTTON_Y,
			KeyEvent.KEYCODE_BUTTON_Z,
			KeyEvent.KEYCODE_BUTTON_L1,
			KeyEvent.KEYCODE_BUTTON_R1,
			KeyEvent.KEYCODE_BUTTON_L2,
			KeyEvent.KEYCODE_BUTTON_R2,
			KeyEvent.KEYCODE_BUTTON_THUMBL,
			KeyEvent.KEYCODE_BUTTON_THUMBR,
			KeyEvent.KEYCODE_BUTTON_START,
			KeyEvent.KEYCODE_BUTTON_SELECT,
			KeyEvent.KEYCODE_BUTTON_MODE,
			KeyEvent.KEYCODE_BUTTON_1,
			KeyEvent.KEYCODE_BUTTON_2,
			KeyEvent.KEYCODE_BUTTON_3,
			KeyEvent.KEYCODE_BUTTON_4 -> true
			else -> false
		}
	}

	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		// SDLActivity normally performs this; do it here for FlutterActivity so
		// SDL Android JNI state is ready (audio + input backends).
		try {
			SDL.setupJNI()
			SDL.initialize()
			SDL.setContext(this)
		} catch (t: Throwable) {
			Log.w(TAG, "SDL Java init failed", t)
		}
	}

	private fun sendGamepadEvent(e: Map<String, Any>) {
		runOnUiThread { gamepadEventSink?.success(e) }
	}

	override fun dispatchKeyEvent(event: KeyEvent): Boolean {
		val fromPad = isGamepadDevice(event.deviceId)
		val gamepadLikeKey = isLikelyGamepadKey(event.keyCode)
		val fromExternalDevice = event.deviceId != KeyCharacterMap.VIRTUAL_KEYBOARD
		
		// Debug: log ALL key events to find what's causing game restarts
		if (event.action == KeyEvent.ACTION_DOWN || event.action == KeyEvent.ACTION_UP) {
			val action = if (event.action == KeyEvent.ACTION_DOWN) "DOWN" else "UP"
			Log.d(TAG, "KeyEvent: keyCode=${event.keyCode} action=$action deviceId=${event.deviceId} fromPad=$fromPad gamepadKey=$gamepadLikeKey external=$fromExternalDevice")
		}

		if (fromPad || (gamepadLikeKey && fromExternalDevice)) {
			// Always swallow navigation keys from gamepads
			when (event.keyCode) {
				KeyEvent.KEYCODE_BACK,
				KeyEvent.KEYCODE_BUTTON_MODE -> return true
			}

			if (event.action != KeyEvent.ACTION_DOWN && event.action != KeyEvent.ACTION_UP) {
				return true
			}
			// Forward button press/release events to Flutter for joystick mapping
			val type = if (event.action == KeyEvent.ACTION_DOWN) "key_down" else "key_up"
			sendGamepadEvent(mapOf("type" to type, "keyCode" to event.keyCode, "deviceId" to event.deviceId))
			return true
		}
		
		// Log if we're letting a key through to SDL (potential problem source)
		if (event.action == KeyEvent.ACTION_DOWN) {
			Log.w(TAG, "Key PASSED TO SDL: keyCode=${event.keyCode} deviceId=${event.deviceId}")
		}
		return super.dispatchKeyEvent(event)
	}

	override fun onGenericMotionEvent(event: MotionEvent): Boolean {
		if (isGamepadDevice(event.deviceId)) {
			// Send normalized axis values for left stick and D-pad hat
			val axisX = event.getAxisValue(MotionEvent.AXIS_X).toDouble()
			val axisY = event.getAxisValue(MotionEvent.AXIS_Y).toDouble()
			val hatX  = event.getAxisValue(MotionEvent.AXIS_HAT_X).toDouble()
			val hatY  = event.getAxisValue(MotionEvent.AXIS_HAT_Y).toDouble()
			sendGamepadEvent(mapOf(
				"type" to "motion",
				"deviceId" to event.deviceId,
				"axisX" to axisX,
				"axisY" to axisY,
				"hatX" to hatX,
				"hatY" to hatY,
			))
			return true
		}
		return super.onGenericMotionEvent(event)
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		// --- Gamepad event stream ---
		EventChannel(flutterEngine.dartExecutor.binaryMessenger, GAMEPAD_EVENTS_CHANNEL)
			.setStreamHandler(object : EventChannel.StreamHandler {
				override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
					gamepadEventSink = events
				}
				override fun onCancel(arguments: Any?) {
					gamepadEventSink = null
				}
			})

		// --- Gamepad query / control ---
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GAMEPAD_CHANNEL)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"listGamepads" -> {
						val devices = InputDevice.getDeviceIds().toList()
							.mapNotNull { InputDevice.getDevice(it) }
							.filter {
								isGamepadDevice(it.id) ||
								(it.id != KeyCharacterMap.VIRTUAL_KEYBOARD && !it.isVirtual)
							}
							.map { d ->
								mapOf(
									"id"   to d.id,
									"name" to d.name,
								)
							}
						result.success(devices)
					}
					else -> result.notImplemented()
				}
			}

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			ARCHIVE_AUTH_CHANNEL,
		).setMethodCallHandler { call, result ->
			val cookieManager = CookieManager.getInstance()
			when (call.method) {
				"getArchiveCookies" -> {
					cookieManager.setAcceptCookie(true)
					result.success(cookieManager.getCookie("https://archive.org"))
				}
				"clearArchiveCookies" -> {
					cookieManager.removeAllCookies { _ ->
						cookieManager.flush()
						result.success(true)
					}
				}
				else -> result.notImplemented()
			}
		}

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			ARCHIVE_EXTRACT_CHANNEL,
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"list7zEntries" -> {
					try {
						val archivePath = call.argument<String>("archivePath")
						if (archivePath == null) {
							result.error("INVALID_ARGS", "archivePath is required", null)
							return@setMethodCallHandler
						}

						val archiveFile = File(archivePath)
						if (!archiveFile.exists()) {
							result.error("FILE_NOT_FOUND", "Archive file not found: $archivePath", null)
							return@setMethodCallHandler
						}

						val entries = mutableListOf<String>()
						SevenZFile(archiveFile).use { sevenZFile ->
							var entry = sevenZFile.nextEntry
							while (entry != null) {
								if (!entry.isDirectory) {
									val normalizedName = entry.name.replace('\\', '/')
									val lowerName = normalizedName.lowercase()
									if (!normalizedName.contains("..") && SUPPORTED_EXTENSIONS.any { lowerName.endsWith(it) }) {
										entries.add(normalizedName)
									}
								}
								entry = sevenZFile.nextEntry
							}
						}

						result.success(entries)
					} catch (e: Exception) {
						result.error("EXCEPTION", "7z listing failed: ${e.message}", null)
					}
				}
				"extract7zSelected" -> {
					val archivePath = call.argument<String>("archivePath")
					val destinationPath = call.argument<String>("destinationPath")
					val selectedEntriesRaw = call.argument<List<String>>("selectedEntries")
					if (archivePath == null || destinationPath == null || selectedEntriesRaw == null) {
						result.error("INVALID_ARGS", "archivePath, destinationPath, and selectedEntries are required", null)
						return@setMethodCallHandler
					}

					val selectedEntries = selectedEntriesRaw.toSet()
					if (selectedEntries.isEmpty()) {
						result.error("INVALID_ARGS", "selectedEntries is empty", null)
						return@setMethodCallHandler
					}

					Thread {
						try {
							val archiveFile = File(archivePath)
							val destDir = File(destinationPath)

							if (!archiveFile.exists()) {
								runOnUiThread {
									result.error("FILE_NOT_FOUND", "Archive file not found: $archivePath", null)
								}
								return@Thread
							}
							destDir.mkdirs()

							var extractedCount = 0
							SevenZFile(archiveFile).use { sevenZFile ->
								var entry = sevenZFile.nextEntry
								while (entry != null) {
									if (!entry.isDirectory) {
										val normalizedName = entry.name.replace('\\', '/')
										val lowerName = normalizedName.lowercase()

										if (!normalizedName.contains("..") && selectedEntries.contains(normalizedName) && SUPPORTED_EXTENSIONS.any { lowerName.endsWith(it) }) {
											val baseName = normalizedName.substringAfterLast('/')
											if (baseName.isBlank()) {
												entry = sevenZFile.nextEntry
												continue
											}
											val outputFile = File(destDir, baseName)
											outputFile.parentFile?.mkdirs()
											outputFile.outputStream().use { output ->
												val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
												while (true) {
													val read = sevenZFile.read(buffer)
													if (read <= 0) {
														break
													}
													output.write(buffer, 0, read)
												}
											}
											extractedCount += 1
											if (extractedCount >= selectedEntries.size) {
												break
											}
										}
									}
									entry = sevenZFile.nextEntry
								}
							}

							if (extractedCount == 0) {
								runOnUiThread {
									result.error("NO_GAME_FILES", "No selected supported game files were extracted.", null)
								}
								return@Thread
							}

							runOnUiThread { result.success(true) }
						} catch (e: Exception) {
							runOnUiThread {
								result.error("EXCEPTION", "Selective 7z extraction failed: ${e.message}", null)
							}
						}
					}.start()
				}
				"extract7z" -> {
					val archivePath = call.argument<String>("archivePath")
					val destinationPath = call.argument<String>("destinationPath")
					if (archivePath == null || destinationPath == null) {
						result.error("INVALID_ARGS", "archivePath and destinationPath are required", null)
						return@setMethodCallHandler
					}

					Thread {
						try {
							val archiveFile = File(archivePath)
							val destDir = File(destinationPath)

							if (!archiveFile.exists()) {
								runOnUiThread {
									result.error("FILE_NOT_FOUND", "Archive file not found: $archivePath", null)
								}
								return@Thread
							}
							destDir.mkdirs()

							var extractedCount = 0
							SevenZFile(archiveFile).use { sevenZFile ->
								var entry = sevenZFile.nextEntry
								while (entry != null) {
									if (!entry.isDirectory) {
										val normalizedName = entry.name.replace('\\', '/')
										val lowerName = normalizedName.lowercase()

										if (!normalizedName.contains("..") && SUPPORTED_EXTENSIONS.any { lowerName.endsWith(it) }) {
											val baseName = normalizedName.substringAfterLast('/')
											if (baseName.isBlank()) {
												entry = sevenZFile.nextEntry
												continue
											}
											val outputFile = File(destDir, baseName)
											outputFile.parentFile?.mkdirs()
											outputFile.outputStream().use { output ->
												val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
												while (true) {
													val read = sevenZFile.read(buffer)
													if (read <= 0) {
														break
													}
													output.write(buffer, 0, read)
												}
											}
											extractedCount += 1
										}
									}
									entry = sevenZFile.nextEntry
								}
							}

							if (extractedCount == 0) {
								runOnUiThread {
									result.error("NO_GAME_FILES", "Archive extracted but no supported game files were found.", null)
								}
								return@Thread
							}

							runOnUiThread { result.success(true) }
						} catch (e: Exception) {
							runOnUiThread {
								result.error("EXCEPTION", "7z extraction failed: ${e.message}", null)
							}
						}
					}.start()
				}
				else -> result.notImplemented()
			}
		}
	}
}
