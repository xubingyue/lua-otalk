local M = {};

local Jingle = require "basejingle";

local global = {
    c = {},
    v = {},
    conf = {},
    sessions = {},
    peers = {},
    iceServers = {},
    prepareSession = {},
};

local features = {
    "urn:xmpp:jingle:1",
    "urn:xmpp:jingle:apps:rtp:1",
    "urn:xmpp:jingle:apps:rtp:audio",
    "urn:xmpp:jingle:apps:rtp:video",
    "urn:xmpp:jingle:apps:rtp:rtcb-fb:0",
    "urn:xmpp:jingle:apps:rtp:rtp-hdrext:0",
    "urn:xmpp:jingle:apps:rtp:ssma:0",
    "urn:xmpp:jingle:apps:dtls:0",
    "urn:xmpp:jingle:apps:grouping:0",
    "urn:xmpp:jingle:apps:file-transfer:3",
    "urn:xmpp:jingle:transports:ice-udp:1",
    "urn:xmpp:jingle:transports.dtls-sctp:1",
    "urn:ietf:rfc:3264",
    "urn:ietf:rfc:5576",
    "urn:ietf:rfc:5888",
    "http://jitsi.org/protocol/colibri"
};

local xmlns_jingle = "urn:xmpp:jingle:1";
local xmlns_jingle_error = "urn:xmpp:jingle:errors:1";


M.newSession = function (o)
    o.client = global.c;
    o.verse = global.v;
    local session = {};
    local peer = o.peer;
    o.local_state = {};
    o.remote_state = {};
    if global.conf["createSession"] then
        session = global.conf["createSession"](o);
    else
        session = Jingle:new(o);
    end

    if not global.peers[peer] then
        global.peers[peer] = {};
    end

    table.insert(global.peers[peer], session);
    global.sessions[o.sid] = session;

    return session;
end

M.closeSession = function (id)
end

M.addICEServer = function (server)
    table.insert(global.iceServers, server);
end

M.endPeerSessions = function (peer, reason, silent)
end

M.getSessionBySID = function (sid)
    return global.sessions[sid];
end

M.onSessionTerminate = function (req, sid)
    global.c:send(verse.reply(req));

    local sessionIndex
    for i, session in ipairs(global.sessions) do
        if sid == session.sid then
            sessionIndex = i
            break
        end
    end

    table.remove(global.sessions, sessionIndex)

    global.c:event("jingle/session-terminate", sid)
    return true
end

M.handle = function (req)
    local tag = req:get_child('jingle', xmlns_jingle);
    local sid = tag.attr.sid;
    local session = global.sessions[sid];
    local rid = req.attr.id;
    local type = req.attr.type;
    local sender = req.attr.from;

    if type == "error" then
        local error_tag = req:get_child('error');
        local tie_break = false;
        if (error_tag) then
            local tie_break_tag = error_tag:get_child('tie-break', xmlns_jingle_error);
            if (tie_break_tag) then
                tie_break = true;
            end
        end
        if (session and tie_break and self.isPending) then
            session:close("alternative-session");
        else
            if (session) then
                session.pendingAction = false;
            end
        end
        return global.c:event("jingle-error", req);
    end

    if type == "result" then
        if session then
            session.pendingAction = false;
        end
        return;
    end

    local action = tag.attr.action;

    local descriptionTypes = {};
    local dTCount = 0;
    for child_tag in tag:children() do
        if child_tag.name == "content" then
            local description_tag = child_tag:child_with_name("description");
            if description_tag and description_tag.attr.media then
                dTCount = dTCount + 1;
                descriptionTypes[description_tag.attr.media.."/"..description_tag.attr.xmlns] = true;
            end
        end
        if child_tag.name == "transport" then
            --something something transport type
        end
    end

    if action ~= "session-initiate" then
        if not session then
            print("Uknown jingle session "..sid);
            local error_stanza = global.v.error_reply(req, 'cancel', 'item-not-found'):tag("unknown-session", { xmlns = xmlns_jingle_error }):up();
            global.c:send(error_stanza);
            return true;
        end

        if session.peerID ~= sender or session:check('ended') then
            print("Session has ended or action has the wrong sender");
            local error_stanza = req:error_reply('cancel', 'conflict'):tag("tie-break", {xmlns = xmlns_jingle_error}):up();
            global.c:send(error_stanza);
            return true;
        end

        if action == "session-accept" and not session.isPending then
            print("Tried to accept the session more than once");
            local error_stanza = req:error_reply('cancel', 'unexpected-request'):tag("out-of-order", {xmlns = xmlns_jingle_error}):up();
            global.c:send(error_stanza);
            return true;
        end

        if action ~= "session-terminate" and action == session.pendingAction then
            print("Tie break during pending request");
            local error_stanza = req:error_reply('cancel', 'conflict'):tag("tie-break", {xmlns = xmlns_jingle_error}):up();
            global.c:send(error_stanza);
            return true;
        end

    elseif (session) then
        if session.peerID ~= sender then
            print("Duplicate sid from new sender");
            local error_stanza = req:error_reply('cancel', "service-unavailable");
            global.c:send(error_stanza);
            return true;
        end

        if session.isPending then
            if c.bound > session.peerID then
                print("Tie break new session because of duplicate sids");
                local error_stanza = req:error_reply('cancel', 'conflict'):tag("tie-break", {xmlns = xmlns_jingle_error}):up();
                global.c:send(error_stanza);
                return true;
            end
        else
            print("Someone is doing this wrong");
            local error_stanza = req:error_reply('cancel', 'unexpected-request'):tag("out-of-order", {xmlns = xmlns_jingle_error}):up();
            global.c:send(error_stanza);
            return true;
        end

    elseif (global.peers[sender] and #global.peers[sender] > 0) then
        --it's a tie!
        for sess_idx, sess in ipairs(global.peers[sender]) do
            if sess and sess.isPending then
                local conflict = false;
                for desc_idx, desc_bool in pairs(descriptionTypes) do
                    if session.pendingDescriptionTypes[desc_idx] then
                        conflict = true;
                        break;
                    end
                end
                if conflict and sess.sid > sid then
                    --we won the tie breaker
                    print("Tie break");
                    local error_stanza = req:error_reply('cancel', 'conflict'):tag("tie-break", {xmlns = xmlns_jingle_error}):up();
                    global.c:send(error_stanza);
                    return true;
                end
            end
        end
    end

    if action == "session-initiate" then
        --for reals this time
        if dTCount == 0 then
            print("session initiate has nothing we need");
            local error_stanza = global.v.error_reply(req, 'cancel', 'bad-reqeust');
            global.c:send(error_stanza);
            return true;
        end

        local new_session = M.newSession({
            sid = sid,
            peer = req.attr.from,
            peerID = sender,
            initiator = false,
            descriptionTypes = descriptionTypes,
            transportTypes = transportTypes,
            req = req,
        });

        return new_session:process(action, req);

    elseif action == "session-terminate" then
        M.onSessionTerminate(req, sid)

    elseif session then
        return session:process(action, req);
    end
end;

M.init = function (verse, client, conf)
    global.v = verse;
    global.c = client;
    global.conf = conf;
    global.c:hook("iq/"..xmlns_jingle, M.handle);
    for key, feature in pairs(features) do
        global.c:add_disco_feature(feature);
    end
end

return M;
