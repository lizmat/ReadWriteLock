# ReadWriteLock

... A lock with shared/exclusive access modes, for the Raku language.

## Features

* Does what a basic `Lock` does, just slower and with more bugs ;)
* Reentrant: the lock can be taken again by a thread that is already holding it
  It needs to be unlocked the same number of times it was locked before it can
  be taken by another thread
* Fair in the sense of first-come-first-serve
* Shared access: multiple 'readers' can share the lock, yet access is mutually
  exclusive between 'readers' and 'writers'
* Lock Upgrade: you can upgrade a shared access mode to an exclusive without
  unlocking first, if no other thread is interferring. In this case you do not
  need to unlock twice.

## Planned Features

* Read-for-write access mode that guarantees that a lock upgrade can be taken
* Async version that returns threads to the threadpool and returns a promise
  from lock()

## Example Usage

```
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
```

## Documentation

Please see the POD in lib/ReadWriteLock.rakumod for more documentation and usage
scenarios.

## License

ReadWriteLock is licensed under the [Artistic License 2.0](https://opensource.org/licenses/Artistic-2.0).

## Feedback and Contact

Please let me know what you think: Robert Lemmen <robertle@semistable.com>
