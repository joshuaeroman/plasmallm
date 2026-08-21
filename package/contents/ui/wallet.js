/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.import "walletCore.js" as Core

function walletName() { return Core.WALLET_NAME || "kdewallet"; }
function walletFolder() { return Core.WALLET_FOLDER || "PlasmaLLM"; }
function walletAppId() { return Core.WALLET_APPID || "PlasmaLLM"; }

function call(dbus, member, args, resolve, reject) {
    var reply;
    try {
        reply = dbus.SessionBus.asyncCall({
            service: "org.kde.kwalletd6",
            path: "/modules/kwalletd6",
            iface: "org.kde.KWallet",
            member: member,
            arguments: args
        });
    } catch (e) {
        if (reject) reject(e);
        else if (resolve) resolve(null);
        return;
    }
    reply.finished.connect(function() {
        var err = null;
        var val = null;
        try {
            if (reply.isError)
                err = reply.error;
            else
                val = Core.unwrapDbusValue(reply.value);
        } catch (e2) {
            err = e2;
        }
        try {
            if (reply.destroy)
                reply.destroy();
        } catch (e3) {}
        if (err) {
            if (reject) reject(err);
        } else if (resolve) {
            resolve(val);
        }
    });
}

function withOpen(dbus, onSession) {
    function deadSession() {
        return {
            available: false,
            handle: -1,
            close: function() {},
            read: function(slot, ok) { if (ok) ok(""); },
            write: function(slot, key, done) { if (done) done(false); },
            sync: function(done) { if (done) done(); }
        };
    }

    call(dbus, "open", [walletName(), new dbus.int64(0), walletAppId()],
        function(rawHandle) {
            var handle = Core.coerceHandle(rawHandle);
            if (handle < 0) {
                onSession(deadSession());
                return;
            }

            var folderReady = false;
            var closed = false;

            function close() {
                if (closed)
                    return;
                closed = true;
                call(dbus, "close",
                    [new dbus.int32(handle), new dbus.bool(false), walletAppId()],
                    function() {}, function() {});
            }

            function ensureFolder(done) {
                if (folderReady) {
                    done(true);
                    return;
                }
                call(dbus, "hasFolder",
                    [new dbus.int32(handle), walletFolder(), walletAppId()],
                    function(exists) {
                        if (Core.isTruthyFlag(exists)) {
                            folderReady = true;
                            done(true);
                            return;
                        }
                        call(dbus, "createFolder",
                            [new dbus.int32(handle), walletFolder(), walletAppId()],
                            function(created) {
                                folderReady = created !== false && created !== null && created !== undefined;
                                done(folderReady);
                            },
                            function() { done(false); }
                        );
                    },
                    function() { done(false); }
                );
            }

            function read(slot, ok) {
                call(dbus, "readPassword",
                    [new dbus.int32(handle), walletFolder(), slot, walletAppId()],
                    function(password) { if (ok) ok(Core.passwordText(password)); },
                    function() { if (ok) ok(""); }
                );
            }

            function write(slot, key, done) {
                ensureFolder(function(okFolder) {
                    if (!okFolder) {
                        if (done) done(false);
                        return;
                    }
                    call(dbus, "writePassword",
                        [new dbus.int32(handle), walletFolder(), slot, key, walletAppId()],
                        function(result) { if (done) done(Core.isWriteSuccess(result)); },
                        function(err) {
                            console.warn("PlasmaLLM: wallet writePassword error:", err);
                            if (done) done(false);
                        }
                    );
                });
            }

            function sync(done) {
                call(dbus, "sync",
                    [new dbus.int32(handle), walletAppId()],
                    function() { if (done) done(); },
                    function() { if (done) done(); }
                );
            }

            function entryList(done) {
                call(dbus, "entryList",
                    [new dbus.int32(handle), walletFolder(), walletAppId()],
                    function(entries) { if (done) done(Core.normalizeStringList(entries)); },
                    function() { if (done) done([]); }
                );
            }

            onSession({
                available: true,
                handle: handle,
                close: close,
                read: read,
                write: write,
                sync: sync,
                entryList: entryList
            });
        },
        function(err) {
            console.warn("PlasmaLLM: KWallet open error:", err);
            onSession(deadSession());
        }
    );
}

function readKey(dbus, primary, extraSlots, fallbackMap, cfgApiKey, onDone) {
    var slots = Core.uniqueSlots([primary].concat(extraSlots || []));
    var fallback = Core.lookupFallback(fallbackMap, slots, cfgApiKey);

    function finish(res) {
        if (onDone) onDone(res);
    }

    withOpen(dbus, function(session) {
        if (!session.available) {
            finish({ available: false, key: fallback, slot: "" });
            return;
        }

        function tryAt(index) {
            if (index >= slots.length) {
                if (fallback) {
                    session.write(primary, fallback, function(ok) {
                        if (ok) {
                            session.sync(function() { session.close(); });
                        } else {
                            session.close();
                        }
                        finish({ available: true, key: fallback, slot: "" });
                    });
                    return;
                }
                session.close();
                finish({ available: true, key: "", slot: "" });
                return;
            }
            var slot = slots[index];
            session.read(slot, function(password) {
                if (password && password.length > 0) {
                    if (slot !== primary) {
                        session.write(primary, password, function() {
                            session.sync(function() { session.close(); });
                        });
                    } else {
                        session.close();
                    }
                    finish({ available: true, key: password, slot: slot });
                    return;
                }
                tryAt(index + 1);
            });
        }

        tryAt(0);
    });
}

function writeKey(dbus, slot, key, onDone) {
    withOpen(dbus, function(session) {
        if (!session.available) {
            if (onDone) onDone({ available: false, success: false });
            return;
        }
        session.write(slot, key, function(ok) {
            if (ok) {
                session.sync(function() {
                    session.close();
                    if (onDone) onDone({ available: true, success: true });
                });
            } else {
                session.close();
                if (onDone) onDone({ available: true, success: false });
            }
        });
    });
}

function copyMissing(dbus, pairs, onDone) {
    pairs = pairs || [];
    withOpen(dbus, function(session) {
        if (!session.available) {
            if (onDone) onDone({ openFailed: true, writes: 0, available: false });
            return;
        }

        var i = 0;
        var writes = 0;

        function next() {
            if (i >= pairs.length) {
                if (writes > 0) {
                    session.sync(function() {
                        session.close();
                        if (onDone) onDone({ openFailed: false, writes: writes, available: true });
                    });
                } else {
                    session.close();
                    if (onDone) onDone({ openFailed: false, writes: 0, available: true });
                }
                return;
            }
            var pair = pairs[i++];
            session.read(pair.from, function(pw) {
                if (!pw) {
                    next();
                    return;
                }
                session.read(pair.to, function(existing) {
                    if (existing) {
                        next();
                        return;
                    }
                    session.write(pair.to, pw, function(ok) {
                        if (ok) writes++;
                        next();
                    });
                });
            });
        }

        next();
    });
}

function listEntries(dbus, onDone) {
    withOpen(dbus, function(session) {
        if (!session.available) {
            if (onDone) onDone({ openFailed: true, entries: [] });
            return;
        }
        session.entryList(function(entries) {
            session.close();
            if (onDone) onDone({ openFailed: false, entries: entries || [] });
        });
    });
}
