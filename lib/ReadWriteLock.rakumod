
enum AccessMode <shared exclusive>;

class ReadWriteLock {

    method lock(AccessMode $access) {
    }

    method unlock() {
    }

    method lock_shared() {
        self.lock(shared);
    }

    method lock_exclusive() {
        self.lock(exclusive);
    }

    # the proto is to avoid LEAVE being run when called with bad args, stolen
    # from Lock in core
    proto method protect(|) {*}
    multi method protect(AccessMode $access, &code) {
        self.lock($access);
        LEAVE {
            self.unlock();
        }
        code()
    }

    method protect_shared(&code) {
        self.protect(shared, &code);
    }

    method protect_exclusive(&code) {
        self.protect(exclusive, &code);
    }
}
