enum AccessMode <shared exclusive>;

# we want to be able to compare AccessModes for an "implied-in" predicate,
# where e.g. exclusive access includes everything you can do with shared access
sub infix:<\<=>(AccessMode $a, AccessMode $b) {
    $a == shared || $b == exclusive;
}

sub infix:<\>=>(AccessMode $a, AccessMode $b) {
    $a == exclusive || $b == shared;
}

class ReadWriteLock {

    class WaitGroup {
        has $.access is rw;
        has %.threads;  # thread-id -> count of reentrant lock() calls
        has $.cond;
    };

    has $!latch = Lock.new;
    has @!wait-groups;

    method lock(AccessMode $access -->  Nil) {
        $!latch.protect({
            # Case A: noone is currently holding the lock, easy!
            if ! @!wait-groups {
                @!wait-groups.push(WaitGroup.new(
                    access => $access,
                    threads => ($*THREAD.id => 1),
                    cond => $!latch.condition));
            }
            # Case B: we already hold the lock in a access mode equal or
            # better to the one requested, just reenter it
            elsif      @!wait-groups.head.threads{$*THREAD.id}
                    && $access <= @!wait-groups.head.access {
                @!wait-groups.head.threads{$*THREAD.id}++;
            }
            # Case C: we want shared access and can join the last waitgroup
            elsif $access == shared && @!wait-groups.tail.access == shared {
                my $joined-wg = @!wait-groups.tail;
                @!wait-groups.tail.threads{$*THREAD.id} = 1;
                while not $joined-wg === @!wait-groups.head {
                    $joined-wg.cond.wait();
                }
            }
            # Case D: we want to upgrade the lock from shared to exclusive
            elsif      $access == exclusive
                    && @!wait-groups.head.access == shared
                    && @!wait-groups.head.threads{$*THREAD.id} {
                if not @!wait-groups.head === @!wait-groups.tail {
                    # there is another waitgroup inbetween, which is exclusive
                    # otherwise it would have been added to the head waitgroup
                    # which is shared. so we cannot upgrade the lock
                    die "Attempt to upgrade ReadWriteLock blocked by other thread";
                }
                else {
                    while @!wait-groups.head.threads.elems > 1 {
                        # we just need to wait until we have the waitgroup for
                        # ourselves
                        @!wait-groups.head.cond.wait();
                    }
                    # ... and then we can upgrade it
                    @!wait-groups.head.access = exclusive;
                }
                # interestingly the case E below does the right thing if there
                # are still other shared threads in the waitgroup we want to
                # upgrade
            }
            # Case E: otherwise we add a new waitgroup to the end
            else {
                my $new-wg = WaitGroup.new(
                    access => $access,
                    threads => ($*THREAD.id => 1),
                    cond => $!latch.condition);
                @!wait-groups.push($new-wg);
                while not $new-wg === @!wait-groups.head {
                    $new-wg.cond.wait();
                }
            }
        });
    }

    method unlock() {
        $!latch.protect({
            # Case A: we do not actually hold the lock
            if ! @!wait-groups || ! @!wait-groups.head.threads{$*THREAD.id} {
                die "Attempt to unlock ReadWriteLock by thread not holding it";
            }
            # Case B: we do currently hold the lock, so reduce our lock count
            # and remove ourselves from the waitgroup if it reaches 0
            elsif @!wait-groups.head.threads{$*THREAD.id} {
                if --@!wait-groups.head.threads{$*THREAD.id} == 0 {
                    @!wait-groups.head.threads{$*THREAD.id}:delete;
                    # which is great, because now finally someone else can have
                    # their turn...
                    if ! @!wait-groups.head.threads {
                        @!wait-groups.shift;
                    }
                    # XXX we only need this outside the previous if for
                    # upgrades, optimize to avoid spurious wakeups
                    if @!wait-groups {
                        @!wait-groups.head.cond.signal_all;
                    }
                }
            }
        });
    }

    method lock-shared() {
        self.lock(shared);
    }

    method lock-exclusive() {
        self.lock(exclusive);
    }

    # the proto is to avoid LEAVE being run when called with bad args, stolen
    # from Lock in core
    proto method protect(|) {*}
    multi method protect(AccessMode $access, &code) {
        self.lock($access);
        LEAVE self.unlock;
        code()
    }

    method protect-shared(&code) {
        self.protect(shared, &code);
    }

    method protect-exclusive(&code) {
        self.protect(exclusive, &code);
    }
}

# vim: expandtab shiftwidth=4
