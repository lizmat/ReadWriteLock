# XXX design question: outside the module namespace? does that not pollute the
# global namespace? should enums start with an uppercase?
enum AccessMode <shared exclusive>;

# we want to be able to compare AccessModes for an "implied-in" predicate,
# where e.g. exclusive access includes everything you can do with shared access 
# XXX design question: use these ordering predicates/operators
# or an explicit method like 
sub infix:<\<=>(AccessMode $a, AccessMode $b) {
    return $a == shared || $b == exclusive;
}

sub infix:<\>=>(AccessMode $a, AccessMode $b) {
    return $a == exclusive || $b == shared;
}

class ReadWriteLock {

    class WaitGroup {
        has $.access;
        has %.threads;  # thread-id -> count of reentrant lock() calls
        has $.cond;     # XXX experiments show that calling .condition on a 
                        # Lock yields independent condition variables, not the
                        # same one. the docs should say so however,
                        # ConditionVariabale docs a a bit LTA anyway
    };

    # XXX design question: layer on top of Lock from core, or use NQP directly?
    # the Lock class seems thin enough that the overhead is ok, and it's kinda
    # cleaner for a module...
    has $!latch = Lock.new();
    has @!wait-groups = ();

    # XXX design question: have an access mode here, or lock-shared() etc like below?
    # the latter is kinda explicit and nice, the former is more generic and
    # allws to pass the mode in from somewhere else, compute it etc. also when
    # we allow upgrades, it would read weird to do lock-upgrade, should be
    # upgrade-lock. on the other hand, perhaps that should just be a
    # lock-exclusive and the lock figures out that it is an upgrade (needs to
    # anyway)
    method lock(AccessMode $access) {
        $!latch.protect({
            # Case A: noone is currently holding the lock, easy!
            if ! @!wait-groups {
                @!wait-groups.push(WaitGroup.new(
                    access => $access,
                    threads => ($*THREAD.id => 1),
                    cond => Any)); # we do not even need one in this case!
                return;
            }
            # Case B: we already hold the lock in a access mode equal or
            # better to the one requested, just reenter it
            elsif      @!wait-groups.head.threads{$*THREAD.id} 
                    && $access <= @!wait-groups.head.access {
                @!wait-groups.head.threads{$*THREAD.id}++;
                return;
            }
            # Case C: we want shared access and can join the last waitgroup
            elsif $access == shared && @!wait-groups.tail.access == shared {
                my $joined-wg = @!wait-groups.tail;
                @!wait-groups.tail.threads{$*THREAD.id} = 1;
                while not $joined-wg === @!wait-groups.head {
                    $joined-wg.cond.wait();
                }
                return;
            }
            # Case D: otherwise we add a new waitgroup to the end
            else {
                my $new-wg = WaitGroup.new(
                    access => $access,
                    threads => ($*THREAD.id => 1),
                    cond => $!latch.condition);
                @!wait-groups.push($new-wg);
                while not $new-wg === @!wait-groups.head {
                    $new-wg.cond.wait();
                }
                return;
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
                        if @!wait-groups {
                            @!wait-groups.head.cond.signal_all;
                        }
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

    # XXX not really a problem, but the protect() access pattern is arguably
    # preferable to explicit lock/unlock where possible (i.e. if the caller
    # isn't doing anything especially dangerous and fun like overhand locking.
    # yet how does that work with upgrades? do you want to call lock-exclusive()
    # inside a protect-shared block? that looks confusing...
    #
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

    method protect-shared(&code) {
        self.protect(shared, &code);
    }

    method protect-exclusive(&code) {
        self.protect(exclusive, &code);
    }
}
