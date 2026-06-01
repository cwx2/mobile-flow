/// connection_config.dart — Connection lifecycle constants.
///
/// Centralises all heartbeat, reconnect, and timeout parameters
/// so they are easy to tune without hunting through business code.
/// These are client-side behavioural constants — not in Agent config
/// because they govern App-side timers and retry logic.
library;

/// TCP + WebSocket handshake timeout for initial and reconnect attempts.
const kConnectTimeout = Duration(seconds: 10);

/// Auth handshake timeout (waiting for auth.result after auth.connect).
const kAuthTimeout = Duration(seconds: 5);

/// Interval between heartbeat pings.
///
/// 10s balances responsive disconnect detection (2 misses = 20s)
/// with minimal network/battery overhead on mobile. Each ping is
/// only a few dozen bytes over an already-open WebSocket.
const kHeartbeatInterval = Duration(seconds: 10);

/// Maximum wait time for a single pong response.
const kHeartbeatTimeout = Duration(seconds: 10);

/// Number of consecutive missed heartbeats before declaring the
/// connection dead. A single miss may be transient network jitter;
/// two consecutive misses strongly indicate a real outage.
const kMaxMissedHeartbeats = 2;

/// Delay before sending the first heartbeat ping after connecting.
///
/// Gives the connection a moment to stabilise so the first RTT
/// measurement is representative, and the user sees a latency
/// number quickly instead of "Measuring..." for 25 seconds.
const kFirstHeartbeatDelay = Duration(seconds: 2);

/// Base delay for exponential backoff on reconnect.
const kReconnectBaseDelay = Duration(seconds: 1);

/// Maximum delay cap for reconnect backoff.
const kReconnectMaxDelay = Duration(seconds: 30);

/// Random jitter added/subtracted to reconnect delay to prevent
/// thundering-herd when multiple clients reconnect simultaneously.
const kReconnectJitter = Duration(milliseconds: 500);

/// Maximum number of reconnect attempts before giving up and
/// transitioning to the failed state.
const kReconnectMaxAttempts = 10;

// ── Stream Watchdog ──

/// Watchdog timeout for the thinking phase (waiting for first chunk).
/// Longer because the AI may take time to start generating.
const kWatchdogThinkingTimeout = Duration(seconds: 60);

/// Watchdog timeout for the active streaming phase (between chunks).
/// Shorter because once streaming starts, chunks should arrive frequently.
const kWatchdogStreamingTimeout = Duration(seconds: 30);

/// Watchdog timeout while a tool is running.
/// Extended because tools (file operations, searches) can take longer.
const kWatchdogToolRunningTimeout = Duration(seconds: 120);
