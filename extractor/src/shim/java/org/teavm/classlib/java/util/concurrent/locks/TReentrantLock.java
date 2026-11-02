package org.teavm.classlib.java.util.concurrent.locks;

/**
 * JavaScript is single threaded and jsoup never suspends while holding this lock (it guards
 * parsing only), so tracking the hold count is enough.
 */
public class TReentrantLock {
    private int holds;

    public TReentrantLock() {
    }

    public TReentrantLock(final boolean fair) {
    }

    public void lock() {
        holds++;
    }

    public boolean tryLock() {
        holds++;
        return true;
    }

    public void unlock() {
        if (holds == 0) {
            throw new IllegalMonitorStateException();
        }
        holds--;
    }

    public boolean isLocked() {
        return holds > 0;
    }
}
