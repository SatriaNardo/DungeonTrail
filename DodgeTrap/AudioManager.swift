import AVFoundation
import SpriteKit

final class AudioManager {

    static let shared = AudioManager()

    private var bgmPlayer: AVAudioPlayer?

    // ── Volume knobs (0.0 – 1.0) ──────────────────────────────────────────────
    var bgmVolume: Float = 0.5 {
        didSet { bgmPlayer?.volume = bgmVolume }
    }
    /// Master volume for every one-shot SFX (QMark, XMark, footstep, etc.)
    var sfxVolume: Float = 0.3

    // Active one-shot players kept alive until they finish, then pruned
    private var sfxPlayers: [AVAudioPlayer] = []

    private init() {}

    // MARK: - BGM

    func playBGM() {
        guard let url = Bundle.main.url(forResource: "BGM", withExtension: "mp3") else {
            print("❌ BGM.mp3 not found")
            return
        }
        do {
            bgmPlayer = try AVAudioPlayer(contentsOf: url)
            bgmPlayer?.numberOfLoops = -1
            bgmPlayer?.volume = bgmVolume
            bgmPlayer?.prepareToPlay()
            bgmPlayer?.play()
            print("🎵 BGM started")
        } catch {
            print("❌ Failed to play BGM: \(error)")
        }
    }

    func stopBGM() {
        bgmPlayer?.stop()
        bgmPlayer = nil
    }

    func pauseBGM() { bgmPlayer?.pause() }
    func resumeBGM() { bgmPlayer?.play() }

    // MARK: - Volume helpers

    func setBGMVolume(_ volume: Float) {
        bgmVolume = max(0, min(volume, 1))
    }

    func setSFXVolume(_ volume: Float) {
        sfxVolume = max(0, min(volume, 1))
    }

    // MARK: - One-Shot SFX  (volume-controllable via sfxVolume)

    /// Play any bundled sound file at the current sfxVolume level.
    /// Pass the full filename including extension, e.g. "QMarkSFX.wav".
    func playSFX(_ filename: String, volumeMultiplier: Float = 1.0) {
        let parts    = filename.split(separator: ".", maxSplits: 1).map(String.init)
        let resource = parts.first ?? filename
        let ext      = parts.count > 1 ? parts[1] : ""

        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            print("❌ SFX not found: \(filename)")
            return
        }
        do {
            // Prune finished players before adding a new one
            sfxPlayers = sfxPlayers.filter { $0.isPlaying }

            let player = try AVAudioPlayer(contentsOf: url)
            // Multiply global sfxVolume by the per-sound volume multiplier (clamped to max 1.0)
            player.volume = min(1.0, sfxVolume * volumeMultiplier)
            player.prepareToPlay()
            player.play()
            sfxPlayers.append(player)   // retain until playback ends
        } catch {
            print("❌ Failed to play SFX \(filename): \(error)")
        }
    }

    /// Overload for backwards compatibility including legacy SKNode call
    func playSFX(_ filename: String, on node: SKNode, volumeMultiplier: Float = 1.0) {
        playSFX(filename, volumeMultiplier: volumeMultiplier)
    }
}

