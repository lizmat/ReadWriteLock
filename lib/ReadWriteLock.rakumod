enum AccessMode <shared exclusive>;

# we want to be able to compare AccessModes for an "implied-in" predicate,
# where e.g. exclusive access includes everything you can do with shared access
sub infix:<\<=>(AccessMode $a, AccessMode $b) {
    $a == shared || $b == exclusive;
}

sub infix:<\>=>(AccessMode $a, AccessMode $b) {
    $a == exclusive || $b == shared;
}

=begin pod

=head1 TITLE

ReadWriteLock -- A lock with shared/exclusive access modes

=head1 SYNOPSIS

=begin code :lang<raku>

use ReadWriteLock;

my $l = ReadWriteLock.new;

my $thread-a = Thread.start({
    $l.lock-shared();
    for ^5 {
        sleep 1;
        say "thread A doing something under protection of the lock";
    }
    $l.unlock();
});

my $thread-b = Thread.start({
    $l.protect-shared({
        for ^5 {
            sleep 1;
            say "thread B doing something under protection of the lock";
        }
    });
});

my $thread-c = Thread.start({
    $l.protect-exclusive({
        for ^5 {
            sleep 1;
            say "thread C doing something under exclusive protection of the lock";
        }
    });
});

$thread-a.join;
$thread-b.join;
$thread-c.join;

=end code

=head1 FEATURES

=item Does what a basic C<Lock> does, just slower and with more bugs ;)

=item Reentrant: the lock can be taken again by a thread that is already holding it It needs to be unlocked the same number of times it was locked before it can be taken by another thread

=item Fair in the sense of first-come-first-serve

=item Shared access: multiple 'readers' can share the lock, yet access is mutually exclusive between 'readers' and 'writers'

=item Lock Upgrade: you can upgrade a shared access mode to an exclusive without unlocking first, if no other thread is interferring. In this case you do not need to unlock twice.

=head1 PLANNED FEATURES

=item Read-for-write access mode that guarantees that a lock upgrade can be taken

=item Async version that returns threads to the threadpool and returns a promise from lock()

=head1 DESCRIPTION

This module implements a lock/mutex with shared and exclusive access modes,
so a set of 'readers' could share the lock while 'writers' need exclusive
access. The lock is reentrant, so can be taken multiple times by the same
thread, and fair in the sense of come-first-server-first.

Please note that locks of whatever kind are a very low-level synchronisation
mechanism and inherently difficult to use correctly, where possible
higher-level mechanisms like a C<Channel>, C<Promise> or C<Suppply> should
be used.

=head1 EXAMPLES

=head2 Constructor

=begin code :lang<raku>

use ReadWriteLock;

my $l = ReadWriteLock.new;

=end code

Constructing a ReadWriteLock is very simple and takes no arguments.

=head2 Protecting a Code segment

=begin code :lang<raku>

$l.protect-shared: {
    # code thunk
}

$l.protect-exclusive: {
    # code thunk
}

$l.protect: shared, {
    # code thunk
}

$l.protect: exclusive, {
    # code thunk
}

=end code

The C<protect()> usage pattern has the distinct benefit that it automatically
unlocks in case of e.g. exceptions or whenever the code block is being left. You
can either use the 'long' form like C<protect-shared()>, which is nice and
implicit, or pass the access mode in as an argument, which allows determning it
from a function and passing it around.

=head2 Direct locking/unlocking

=begin code :lang<raku>

$l.lock-shared;

$l.lock-exclusive;

$l.lock(shared);

$l.lock(exclusive);

$l.unlock;

=end code

Alternatively you can also use stand-alone lock/unlock calls, which allows
tricky usages like overhand locking etc, but requires more care to be safe. If
you lock multiple times, you need to unlock a matching number of times before
the lock becomes available again.

=head2 Lock Upgrades

=begin code :lang<raku>

$l.lock-shared;

# do something

$l.lock-exclusive;

# do something else that requires exclusive access

$l.unlock;

=end code

You can upgrade a lock that you are holding in shared mode to an exclusive
access, as long as no other thread was traying to do the same before (You will
get an exception in that case). In this case you only need to unlock once, the
lock has been upgraded not re-entered.

=end pod

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

=begin pod

=head1 AUTHORS

Robert Lemmen (2018-2020), Elizabeth Mattijsen <liz@raku.rocks> (2021-)

Source can be located at: https://github.com/lizmat/ReadWriteLock . Comments and
Pull Requests are welcome.

If you like this module, or what I’m doing more generally, committing to a
L<small sponsorship|https://github.com/sponsors/lizmat/>  would mean a great
deal to me!

=head1 COPYRIGHT AND LICENSE

Copyright 2018-2020 Robert Lemmen, 2021, 2024 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

# vim: expandtab shiftwidth=4
