# The background sync thread and its lock live here, outside reloadable code, so
# a development-mode reload can't lose track of a sync that is still running.
# (Plain Ruby thread on purpose: Solid Queue's fork-based supervisor doesn't work on Windows.)
TRACKER_SYNC_THREAD = Concurrent::AtomicReference.new(nil)
TRACKER_SYNC_LOCK = Mutex.new
