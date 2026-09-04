import { DurableObject } from "cloudflare:workers";

const VERSION = 1;
const MAX_BODY = 64 * 1024;
const MAX_CIPHERTEXT = 48 * 1024;
const RECEIPT_TTL = 24 * 60 * 60 * 1000;
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const text = new TextEncoder();

type Profile = { id: string; trainerName: string; friendCode: string; agreementPublicKey: string };
type FriendState = {
  id: string;
  requesterId: string;
  addresseeId: string;
  status: "pending" | "accepted" | "declined";
  createdAt: number;
  updatedAt: number;
  other: Profile;
};
type Invite = {
  id: string;
  tradeId: string;
  inviterId: string;
  inviteeId: string;
  status: "pending" | "accepted" | "declined";
  createdAt: number;
  other: Profile;
};
type Offer = { nonce: string; ciphertext: string; tag: string; digest: string };
type Receipt = {
  tradeId: string;
  trainerAId: string;
  trainerBId: string;
  manifestDigest: string;
  offerA: Offer;
  offerB: Offer;
  committedAt: number;
  expiresAt: number;
};
type TradeResult = { manifestDigest: string; offerDigest?: string; receipt?: Receipt };

type TrainerRow = {
  id: string;
  token_hash?: string;
  trainer_name: string;
  friend_code: string;
  agreement_public_key: string;
};
type FriendRow = {
  id: string;
  requester_id: string;
  addressee_id: string;
  status: FriendState["status"];
  created_at: number;
  updated_at: number;
  other_id: string;
  other_name: string;
  other_code: string;
  other_agreement_public_key: string;
};
type InviteRow = {
  id: string;
  trade_id: string;
  inviter_id: string;
  invitee_id: string;
  status: Invite["status"];
  created_at: number;
  other_id: string;
  other_name: string;
  other_code: string;
  other_agreement_public_key: string;
};
type TradeRow = {
  trade_id: string;
  trainer_a_id: string;
  trainer_b_id: string;
  status: "invited" | "active" | "committed";
  offer_a: string | null;
  offer_b: string | null;
  offer_a_digest: string | null;
  offer_b_digest: string | null;
  confirm_a: number;
  confirm_b: number;
  manifest_digest: string | null;
  receipt_json: string | null;
  committed_at: number | null;
  expires_at: number | null;
  ack_a: number;
  ack_b: number;
  cleaned_at: number | null;
};

class Failure extends Error {
  constructor(readonly code: string, readonly status = 400) {
    super(code);
    this.name = "Failure";
  }
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const exact = (value: Record<string, unknown>, keys: readonly string[]): void => {
  const expected = new Set(keys);
  if (Object.keys(value).some((key) => !expected.has(key))) throw new Failure("invalid_body");
};

const field = (value: Record<string, unknown>, key: string, min: number, max: number): string => {
  const item = value[key];
  if (typeof item !== "string" || item.length < min || item.length > max) {
    throw new Failure("invalid_body");
  }
  return item;
};

const bytesToBase64 = (value: ArrayBuffer | Uint8Array): string => {
  const bytes = value instanceof Uint8Array ? value : new Uint8Array(value);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "");
};

const base64Bytes = (value: string): Uint8Array | null => {
  if (!/^[A-Za-z0-9+/_=-]+$/u.test(value) || value.length % 4 === 1) return null;
  try {
    const padded = value.replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - (value.length % 4)) % 4);
    const binary = atob(padded);
    return Uint8Array.from(binary, (character) => character.charCodeAt(0));
  } catch {
    return null;
  }
};

const friendCode = (): string => {
  const bytes = new Uint8Array(8);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (byte) => CODE_ALPHABET[byte % CODE_ALPHABET.length]).join("");
};

const digest = async (value: string): Promise<string> =>
  bytesToBase64(await crypto.subtle.digest("SHA-256", text.encode(value)));

const digestBytes = async (value: Uint8Array): Promise<string> => {
  const copy = new ArrayBuffer(value.byteLength);
  new Uint8Array(copy).set(value);
  return bytesToBase64(await crypto.subtle.digest("SHA-256", copy));
};

const profile = (row: TrainerRow): Profile => ({
  id: row.id,
  trainerName: row.trainer_name,
  friendCode: row.friend_code,
  agreementPublicKey: row.agreement_public_key,
});

const json = (value: unknown, status = 200): Response =>
  Response.json(value, { status, headers: { "cache-control": "no-store" } });

const clientErrors = new Set([
  "unauthorized", "not_found", "forbidden", "invalid_body", "invalid_json", "body_too_large",
  "invalid_trainer_name", "invalid_agreement_key", "invalid_token", "already_registered",
  "token_in_use", "friend_not_found", "cannot_friend_self", "request_pending", "invalid_state", "friendship_required",
  "trade_closed", "encrypted_offer_only", "manifest_mismatch", "connection_invalid", "invalid_message",
  "message_too_large",
]);

const errorResponse = (error: unknown): Response => {
  const candidate = error instanceof Failure ? error.code : error instanceof Error ? error.message : "";
  const code = clientErrors.has(candidate) ? candidate : "internal_error";
  const status = error instanceof Failure
    ? error.status
    : code === "unauthorized" ? 401
      : code === "not_found" || code === "friend_not_found" ? 404
        : code === "forbidden" || code === "friendship_required" ? 403
          : code === "request_pending" || code === "already_registered" || code === "token_in_use" || code === "trade_closed" ? 409
            : code === "body_too_large" || code === "message_too_large" ? 413 : code === "internal_error" ? 500 : 400;
  return json({ error: code }, status);
};

const tokenFrom = (request: Request): string | null => {
  const header = request.headers.get("authorization");
  if (!header?.startsWith("Bearer ")) return null;
  const token = header.slice(7);
  return token.length >= 32 && token.length <= 128 ? token : null;
};

const actorHeader = "x-trade-actor";

async function body(request: Request): Promise<Record<string, unknown>> {
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (declared > MAX_BODY) throw new Failure("body_too_large", 413);
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.byteLength > MAX_BODY) throw new Failure("body_too_large", 413);
  let value: unknown;
  try {
    value = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new Failure("invalid_json");
  }
  if (!isRecord(value)) throw new Failure("invalid_body");
  return value;
}

const offerDigestInput = (
  tradeId: string,
  senderId: string,
  recipientId: string,
  nonce: string,
  ciphertext: string,
  tag: string,
): string => `ptb-trade-v1\noffer\n${tradeId}\n${senderId}\n${recipientId}\n${nonce}\n${ciphertext}\n${tag}\n`;

const manifestInput = (
  tradeId: string,
  trainerAId: string,
  trainerBId: string,
  offerADigest: string,
  offerBDigest: string,
): string => `ptb-trade-v1\nmanifest\n${tradeId}\n${trainerAId}\n${trainerBId}\n${offerADigest}\n${offerBDigest}\n`;

const envelope = (type: string, tradeId: string, value: object): string =>
  JSON.stringify({ v: VERSION, messageId: crypto.randomUUID(), type, tradeId, body: value });

export class TradeDatabase extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    void ctx.blockConcurrencyWhile(async () => {
      ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS trainers (
          id TEXT PRIMARY KEY,
          token_hash TEXT NOT NULL UNIQUE,
          trainer_name TEXT NOT NULL,
          friend_code TEXT NOT NULL UNIQUE,
          agreement_public_key TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS friend_requests (
          id TEXT PRIMARY KEY,
          requester_id TEXT NOT NULL,
          addressee_id TEXT NOT NULL,
          status TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          UNIQUE(requester_id, addressee_id)
        );
        CREATE TABLE IF NOT EXISTS trade_invites (
          id TEXT PRIMARY KEY,
          trade_id TEXT NOT NULL UNIQUE,
          inviter_id TEXT NOT NULL,
          invitee_id TEXT NOT NULL,
          status TEXT NOT NULL,
          created_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS trades (
          trade_id TEXT PRIMARY KEY,
          trainer_a_id TEXT NOT NULL,
          trainer_b_id TEXT NOT NULL,
          status TEXT NOT NULL,
          offer_a TEXT,
          offer_b TEXT,
          offer_a_digest TEXT,
          offer_b_digest TEXT,
          confirm_a INTEGER NOT NULL DEFAULT 0,
          confirm_b INTEGER NOT NULL DEFAULT 0,
          manifest_digest TEXT,
          receipt_json TEXT,
          committed_at INTEGER,
          expires_at INTEGER,
          ack_a INTEGER NOT NULL DEFAULT 0,
          ack_b INTEGER NOT NULL DEFAULT 0,
          cleaned_at INTEGER
        );
        CREATE INDEX IF NOT EXISTS friend_request_participants ON friend_requests(requester_id, addressee_id, status);
        CREATE INDEX IF NOT EXISTS invite_participants ON trade_invites(inviter_id, invitee_id, status);
        CREATE INDEX IF NOT EXISTS trade_expiry ON trades(expires_at, cleaned_at);
      `);
    });
  }

  private row<T extends Record<string, SqlStorageValue>>(sql: string, ...args: (string | number | null)[]): T | undefined {
    return this.ctx.storage.sql.exec<T>(sql, ...args).toArray()[0];
  }

  private trainer(id: string): TrainerRow {
    const row = this.row<TrainerRow>("SELECT id, trainer_name, friend_code, agreement_public_key FROM trainers WHERE id = ?", id);
    if (!row) throw new Failure("not_found", 404);
    return row;
  }

  private trade(id: string): TradeRow {
    const row = this.row<TradeRow>("SELECT * FROM trades WHERE trade_id = ?", id);
    if (!row) throw new Failure("not_found", 404);
    return row;
  }

  private participant(trade: TradeRow, id: string): "a" | "b" {
    if (trade.trainer_a_id === id) return "a";
    if (trade.trainer_b_id === id) return "b";
    throw new Failure("forbidden", 403);
  }

  private isFriend(a: string, b: string): boolean {
    return Boolean(this.row("SELECT id FROM friend_requests WHERE status = 'accepted' AND ((requester_id = ? AND addressee_id = ?) OR (requester_id = ? AND addressee_id = ?))", a, b, b, a));
  }

  async register(input: { trainerName: string; agreementPublicKey: string; token: string }): Promise<Profile> {
    const name = typeof input?.trainerName === "string" ? input.trainerName : "";
    if (name.length < 2 || name.length > 20) throw new Failure("invalid_trainer_name");
    const publicKey = typeof input?.agreementPublicKey === "string" ? input.agreementPublicKey : "";
    const token = typeof input?.token === "string" ? input.token : "";
    const publicKeyBytes = base64Bytes(publicKey);
    if (!/^[A-Za-z0-9+/_=-]{80,140}$/u.test(publicKey) || !publicKeyBytes || publicKeyBytes.length !== 65 || publicKeyBytes[0] !== 4) throw new Failure("invalid_agreement_key");
    if (token.length < 32 || token.length > 128) throw new Failure("invalid_token");
    const id = `ptb-trainer-${await digestBytes(publicKeyBytes)}`;
    const tokenHash = await digest(token);
    const existing = this.row<TrainerRow>("SELECT id, token_hash, trainer_name, friend_code, agreement_public_key FROM trainers WHERE id = ?", id);
    if (existing) {
      if (existing.token_hash === tokenHash) return profile(existing);
      throw new Failure("already_registered", 409);
    }
    if (this.row("SELECT id FROM trainers WHERE token_hash = ?", tokenHash)) throw new Failure("token_in_use", 409);
    let code = friendCode();
    while (this.row("SELECT id FROM trainers WHERE friend_code = ?", code)) code = friendCode();
    const now = Date.now();
    this.ctx.storage.sql.exec(
      "INSERT INTO trainers (id, token_hash, trainer_name, friend_code, agreement_public_key, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
      id,
      tokenHash,
      name,
      code,
      publicKey,
      now,
      now,
    );
    return { id, trainerName: name, friendCode: code, agreementPublicKey: publicKey };
  }

  async authenticate(token: string): Promise<Profile | null> {
    if (typeof token !== "string" || token.length < 32 || token.length > 128) return null;
    const tokenHash = await digest(token);
    const row = this.row<TrainerRow>("SELECT id, trainer_name, friend_code, agreement_public_key FROM trainers WHERE token_hash = ?", tokenHash);
    return row ? profile(row) : null;
  }

  async updateTrainer(id: string, input: { trainerName: string }): Promise<Profile> {
    this.trainer(id);
    const name = typeof input?.trainerName === "string" ? input.trainerName : "";
    if (name.length < 2 || name.length > 20) throw new Failure("invalid_trainer_name");
    this.ctx.storage.sql.exec("UPDATE trainers SET trainer_name = ?, updated_at = ? WHERE id = ?", name, Date.now(), id);
    return profile(this.trainer(id));
  }

  async friends(id: string): Promise<{ friends: Profile[]; requests: FriendState[] }> {
    this.trainer(id);
    const rows = this.ctx.storage.sql.exec<FriendRow>(
      `SELECT f.id, f.requester_id, f.addressee_id, f.status, f.created_at, f.updated_at,
        t.id AS other_id, t.trainer_name AS other_name, t.friend_code AS other_code,
        t.agreement_public_key AS other_agreement_public_key
       FROM friend_requests f JOIN trainers t ON t.id = CASE WHEN f.requester_id = ? THEN f.addressee_id ELSE f.requester_id END
       WHERE f.requester_id = ? OR f.addressee_id = ? ORDER BY f.created_at`,
      id,
      id,
      id,
    ).toArray();
    const requests = rows.map((row) => ({
      id: row.id,
      requesterId: row.requester_id,
      addresseeId: row.addressee_id,
      status: row.status,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      other: { id: row.other_id, trainerName: row.other_name, friendCode: row.other_code, agreementPublicKey: row.other_agreement_public_key },
    }));
    return {
      friends: requests.filter((request) => request.status === "accepted").map((request) => request.other),
      requests,
    };
  }

  async requestFriend(id: string, input: { friendCode: string }): Promise<FriendState> {
    this.trainer(id);
    const code = typeof input?.friendCode === "string" ? input.friendCode : "";
    const target = this.row<TrainerRow>("SELECT id, trainer_name, friend_code, agreement_public_key FROM trainers WHERE friend_code = ?", code);
    if (!target) throw new Failure("friend_not_found", 404);
    if (target.id === id) throw new Failure("cannot_friend_self");
    const existing = this.row<FriendRow>(
      "SELECT f.*, t.id AS other_id, t.trainer_name AS other_name, t.friend_code AS other_code, t.agreement_public_key AS other_agreement_public_key FROM friend_requests f JOIN trainers t ON t.id = CASE WHEN f.requester_id = ? THEN f.addressee_id ELSE f.requester_id END WHERE (f.requester_id = ? AND f.addressee_id = ?) OR (f.requester_id = ? AND f.addressee_id = ?)",
      id,
      id,
      target.id,
      id,
      target.id,
    );
    const now = Date.now();
    if (existing) {
      if (existing.status === "accepted") return this.friendState(existing);
      if (existing.requester_id !== id) throw new Failure("request_pending", 409);
      this.ctx.storage.sql.exec("UPDATE friend_requests SET status = 'pending', updated_at = ? WHERE id = ?", now, existing.id);
      return this.friendState({ ...existing, status: "pending", updated_at: now });
    }
    const row: FriendRow = {
      id: crypto.randomUUID(),
      requester_id: id,
      addressee_id: target.id,
      status: "pending",
      created_at: now,
      updated_at: now,
      other_id: target.id,
      other_name: target.trainer_name,
      other_code: target.friend_code,
      other_agreement_public_key: target.agreement_public_key,
    };
    this.ctx.storage.sql.exec("INSERT INTO friend_requests (id, requester_id, addressee_id, status, created_at, updated_at) VALUES (?, ?, ?, 'pending', ?, ?)", row.id, id, target.id, now, now);
    return this.friendState(row);
  }

  private friendState(row: FriendRow): FriendState {
    return {
      id: row.id,
      requesterId: row.requester_id,
      addresseeId: row.addressee_id,
      status: row.status,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      other: { id: row.other_id, trainerName: row.other_name, friendCode: row.other_code, agreementPublicKey: row.other_agreement_public_key },
    };
  }

  async acceptFriend(id: string, requestId: string): Promise<FriendState> {
    this.trainer(id);
    const row = this.row<FriendRow>(
      "SELECT f.*, t.id AS other_id, t.trainer_name AS other_name, t.friend_code AS other_code, t.agreement_public_key AS other_agreement_public_key FROM friend_requests f JOIN trainers t ON t.id = f.requester_id WHERE f.id = ?",
      requestId,
    );
    if (!row) throw new Failure("not_found", 404);
    if (row.addressee_id !== id) throw new Failure("forbidden", 403);
    if (row.status === "accepted") return this.friendState(row);
    if (row.status !== "pending") throw new Failure("invalid_state");
    const now = Date.now();
    this.ctx.storage.sql.exec("UPDATE friend_requests SET status = 'accepted', updated_at = ? WHERE id = ?", now, requestId);
    return this.friendState({ ...row, status: "accepted", updated_at: now });
  }

  async invite(id: string, input: { friendCode: string }): Promise<Invite> {
    this.trainer(id);
    const target = this.row<TrainerRow>("SELECT id, trainer_name, friend_code, agreement_public_key FROM trainers WHERE friend_code = ?", input?.friendCode ?? "");
    if (!target) throw new Failure("friend_not_found", 404);
    if (!this.isFriend(id, target.id)) throw new Failure("friendship_required", 403);
    const now = Date.now();
    const invite: Invite = {
      id: crypto.randomUUID(),
      tradeId: crypto.randomUUID(),
      inviterId: id,
      inviteeId: target.id,
      status: "pending",
      createdAt: now,
      other: profile(target),
    };
    const a = id < target.id ? id : target.id;
    const b = id < target.id ? target.id : id;
    this.ctx.storage.sql.exec("INSERT INTO trade_invites (id, trade_id, inviter_id, invitee_id, status, created_at) VALUES (?, ?, ?, ?, 'pending', ?)", invite.id, invite.tradeId, id, target.id, now);
    this.ctx.storage.sql.exec("INSERT INTO trades (trade_id, trainer_a_id, trainer_b_id, status) VALUES (?, ?, ?, 'invited')", invite.tradeId, a, b);
    return invite;
  }

  async invites(id: string): Promise<Invite[]> {
    this.trainer(id);
    return this.ctx.storage.sql.exec<InviteRow>(
      `SELECT i.id, i.trade_id, i.inviter_id, i.invitee_id, i.status, i.created_at,
        t.id AS other_id, t.trainer_name AS other_name, t.friend_code AS other_code,
        t.agreement_public_key AS other_agreement_public_key
       FROM trade_invites i JOIN trainers t ON t.id = CASE WHEN i.inviter_id = ? THEN i.invitee_id ELSE i.inviter_id END
       JOIN trades r ON r.trade_id = i.trade_id
       WHERE (i.inviter_id = ? OR i.invitee_id = ?)
         AND i.status IN ('pending', 'accepted') AND r.status IN ('invited', 'active')
       ORDER BY i.created_at`,
      id,
      id,
      id,
    ).toArray().map((row) => ({
      id: row.id,
      tradeId: row.trade_id,
      inviterId: row.inviter_id,
      inviteeId: row.invitee_id,
      status: row.status,
      createdAt: row.created_at,
      other: { id: row.other_id, trainerName: row.other_name, friendCode: row.other_code, agreementPublicKey: row.other_agreement_public_key },
    }));
  }

  async acceptInvite(id: string, inviteId: string): Promise<{ tradeId: string }> {
    this.trainer(id);
    const row = this.row<InviteRow>("SELECT id, trade_id, inviter_id, invitee_id, status, created_at, inviter_id AS other_id, '' AS other_name, '' AS other_code FROM trade_invites WHERE id = ?", inviteId);
    if (!row) throw new Failure("not_found", 404);
    if (row.invitee_id !== id) throw new Failure("forbidden", 403);
    if (this.trade(row.trade_id).status === "committed") throw new Failure("trade_closed", 409);
    if (row.status === "accepted") return { tradeId: row.trade_id };
    if (row.status !== "pending") throw new Failure("invalid_state");
    this.ctx.storage.sql.exec("UPDATE trade_invites SET status = 'accepted' WHERE id = ?", inviteId);
    this.ctx.storage.sql.exec("UPDATE trades SET status = 'active' WHERE trade_id = ? AND status = 'invited'", row.trade_id);
    return { tradeId: row.trade_id };
  }

  async offer(id: string, tradeId: string, input: { recipientId: string; nonce: string; ciphertext: string; tag: string }): Promise<TradeResult> {
    const trade = this.trade(tradeId);
    if (trade.status !== "active") throw new Failure("trade_closed", 409);
    const side = this.participant(trade, id);
    const recipient = side === "a" ? trade.trainer_b_id : trade.trainer_a_id;
    const recipientId = typeof input?.recipientId === "string" ? input.recipientId : "";
    const nonce = typeof input?.nonce === "string" ? input.nonce : "";
    const ciphertext = typeof input?.ciphertext === "string" ? input.ciphertext : "";
    const tag = typeof input?.tag === "string" ? input.tag : "";
    if (recipientId !== recipient || nonce.length < 8 || nonce.length > 128 || ciphertext.length < 1 || ciphertext.length > MAX_CIPHERTEXT || tag.length < 1 || tag.length > 128) throw new Failure("encrypted_offer_only");
    if (!this.isFriend(trade.trainer_a_id, trade.trainer_b_id)) throw new Failure("friendship_required", 403);
    const offerDigest = await digest(offerDigestInput(tradeId, id, recipient, nonce, ciphertext, tag));
    const value = JSON.stringify({ nonce, ciphertext, tag, digest: offerDigest });
    const offerColumn = side === "a" ? "offer_a" : "offer_b";
    const digestColumn = side === "a" ? "offer_a_digest" : "offer_b_digest";
    this.ctx.storage.sql.exec(`UPDATE trades SET ${offerColumn} = ?, ${digestColumn} = ?, confirm_a = 0, confirm_b = 0, manifest_digest = NULL WHERE trade_id = ? AND status = 'active'`, value, offerDigest, tradeId);
    const latest = this.trade(tradeId);
    if (!latest.offer_a_digest || !latest.offer_b_digest) return { manifestDigest: "", offerDigest };
    const manifestDigest = await digest(manifestInput(tradeId, latest.trainer_a_id, latest.trainer_b_id, latest.offer_a_digest, latest.offer_b_digest));
    this.ctx.storage.sql.exec("UPDATE trades SET manifest_digest = ? WHERE trade_id = ? AND offer_a_digest = ? AND offer_b_digest = ?", manifestDigest, tradeId, latest.offer_a_digest, latest.offer_b_digest);
    return { manifestDigest, offerDigest };
  }

  async confirm(id: string, tradeId: string, manifestDigest: string): Promise<TradeResult> {
    const trade = this.trade(tradeId);
    const side = this.participant(trade, id);
    if (trade.status === "committed") {
      if (trade.manifest_digest !== manifestDigest) throw new Failure("manifest_mismatch");
      return trade.receipt_json
        ? { manifestDigest: trade.manifest_digest ?? manifestDigest, receipt: JSON.parse(trade.receipt_json) as Receipt }
        : { manifestDigest: trade.manifest_digest ?? manifestDigest };
    }
    if (!trade.manifest_digest || trade.manifest_digest !== manifestDigest) throw new Failure("manifest_mismatch");
    const column = side === "a" ? "confirm_a" : "confirm_b";
    this.ctx.storage.sql.exec(`UPDATE trades SET ${column} = 1 WHERE trade_id = ? AND status = 'active'`, tradeId);
    const latest = this.trade(tradeId);
    if (latest.confirm_a !== 1 || latest.confirm_b !== 1) return { manifestDigest };
    const now = Date.now();
    const expiresAt = now + RECEIPT_TTL;
    const receipt: Receipt = {
      tradeId,
      trainerAId: latest.trainer_a_id,
      trainerBId: latest.trainer_b_id,
      manifestDigest,
      offerA: JSON.parse(latest.offer_a ?? "null") as Offer,
      offerB: JSON.parse(latest.offer_b ?? "null") as Offer,
      committedAt: now,
      expiresAt,
    };
    this.ctx.storage.sql.exec("UPDATE trades SET status = 'committed', manifest_digest = ?, receipt_json = ?, committed_at = ?, expires_at = ? WHERE trade_id = ? AND status = 'active'", manifestDigest, JSON.stringify(receipt), now, expiresAt, tradeId);
    await this.ctx.storage.setAlarm(expiresAt);
    return { manifestDigest, receipt };
  }

  async receipt(id: string, tradeId: string): Promise<Record<string, unknown>> {
    const trade = this.trade(tradeId);
    this.participant(trade, id);
    if (trade.status !== "committed") throw new Failure("not_found", 404);
    if (!trade.receipt_json) return { tradeId, manifestDigest: trade.manifest_digest, committedAt: trade.committed_at, cleaned: true };
    return JSON.parse(trade.receipt_json) as Receipt;
  }

  async acknowledge(id: string, tradeId: string, manifestDigest: string): Promise<{ cleaned: boolean }> {
    const trade = this.trade(tradeId);
    const side = this.participant(trade, id);
    if (trade.status !== "committed" || trade.manifest_digest !== manifestDigest) throw new Failure("manifest_mismatch");
    const column = side === "a" ? "ack_a" : "ack_b";
    this.ctx.storage.sql.exec(`UPDATE trades SET ${column} = 1 WHERE trade_id = ?`, tradeId);
    const latest = this.trade(tradeId);
    if (latest.ack_a === 1 && latest.ack_b === 1 && latest.cleaned_at === null) {
      this.ctx.storage.sql.exec("UPDATE trades SET offer_a = NULL, offer_b = NULL, receipt_json = NULL, cleaned_at = ? WHERE trade_id = ?", Date.now(), tradeId);
      await this.scheduleAlarm();
      return { cleaned: true };
    }
    return { cleaned: latest.cleaned_at !== null };
  }

  private async scheduleAlarm(): Promise<void> {
    const next = this.row<{ expires_at: number }>("SELECT MIN(expires_at) AS expires_at FROM trades WHERE status = 'committed' AND cleaned_at IS NULL AND expires_at IS NOT NULL");
    if (next?.expires_at) await this.ctx.storage.setAlarm(next.expires_at);
    else await this.ctx.storage.deleteAlarm();
  }

  async alarm(): Promise<void> {
    const now = Date.now();
    this.ctx.storage.sql.exec("UPDATE trades SET offer_a = NULL, offer_b = NULL, receipt_json = NULL, cleaned_at = ? WHERE status = 'committed' AND cleaned_at IS NULL AND expires_at <= ?", now, now);
    await this.scheduleAlarm();
  }

  async fetch(request: Request): Promise<Response> {
    const match = new URL(request.url).pathname.match(/^\/v1\/trades\/([^/]+)\/ws$/u);
    if (!match || request.headers.get("upgrade")?.toLowerCase() !== "websocket") return errorResponse(new Failure("not_found", 404));
    const tradeId = match[1];
    const actor = request.headers.get(actorHeader);
    if (!actor) return errorResponse(new Failure("unauthorized", 401));
    try {
      const trade = this.trade(tradeId);
      this.participant(trade, actor);
      if (trade.status === "committed") throw new Failure("trade_closed", 409);
      if (trade.status !== "active" || !this.isFriend(trade.trainer_a_id, trade.trainer_b_id)) throw new Failure("friendship_required", 403);
      const pair = new WebSocketPair();
      this.ctx.acceptWebSocket(pair[1], [`trade:${tradeId}`, `actor:${actor}`]);
      pair[1].send(envelope("trade.ready", tradeId, { manifestDigest: trade.manifest_digest }));
      const peer = actor === trade.trainer_a_id ? trade.trainer_b_id : trade.trainer_a_id;
      const stored = actor === trade.trainer_a_id ? trade.offer_b : trade.offer_a;
      if (stored) {
        const offer = JSON.parse(stored) as Offer;
        pair[1].send(envelope("trade.offer", tradeId, {
          senderId: peer,
          recipientId: actor,
          nonce: offer.nonce,
          ciphertext: offer.ciphertext,
          tag: offer.tag,
          digest: offer.digest,
        }));
      }
      return new Response(null, { status: 101, webSocket: pair[0] });
    } catch (error) {
      return errorResponse(error);
    }
  }

  async webSocketMessage(socket: WebSocket, message: string | ArrayBuffer): Promise<void> {
    try {
      const tags = this.ctx.getTags(socket);
      const tradeId = tags.find((tag) => tag.startsWith("trade:"))?.slice(6);
      const actor = tags.find((tag) => tag.startsWith("actor:"))?.slice(6);
      if (!tradeId || !actor) throw new Failure("connection_invalid");
      const raw = typeof message === "string" ? message : new TextDecoder().decode(message);
      if (new TextEncoder().encode(raw).byteLength > MAX_BODY) throw new Failure("message_too_large", 413);
      const parsed: unknown = JSON.parse(raw);
      if (!isRecord(parsed) || parsed.v !== VERSION || typeof parsed.type !== "string" || !isRecord(parsed.body)) throw new Failure("invalid_message");
      if (parsed.type === "trade.offer") {
        exact(parsed.body, ["recipientId", "nonce", "ciphertext", "tag"]);
        const result = await this.offer(actor, tradeId, parsed.body as { recipientId: string; nonce: string; ciphertext: string; tag: string });
        this.broadcast(tradeId, envelope("trade.offer", tradeId, { senderId: actor, ...parsed.body, digest: result.offerDigest }));
        if (result.manifestDigest) this.broadcast(tradeId, envelope("trade.manifest", tradeId, { manifestDigest: result.manifestDigest }));
        return;
      }
      if (parsed.type === "trade.confirm") {
        exact(parsed.body, ["manifestDigest"]);
        const result = await this.confirm(actor, tradeId, field(parsed.body, "manifestDigest", 1, 128));
        if (result.receipt) this.broadcast(tradeId, envelope("trade.committed", tradeId, result.receipt));
        else this.broadcast(tradeId, envelope("trade.confirmed", tradeId, { trainerId: actor, manifestDigest: result.manifestDigest }));
        return;
      }
      if (parsed.type === "trade.ack") {
        exact(parsed.body, ["manifestDigest"]);
        const cleaned = await this.acknowledge(actor, tradeId, field(parsed.body, "manifestDigest", 1, 128));
        this.broadcast(tradeId, envelope("trade.acknowledged", tradeId, { trainerId: actor, cleaned: cleaned.cleaned }));
        return;
      }
      throw new Failure("invalid_message");
    } catch (error) {
      try {
        socket.send(envelope("error", "", { error: error instanceof Failure ? error.code : "invalid_message" }));
      } catch {
        // The peer may have closed while an error was being reported.
      }
    }
  }

  private broadcast(tradeId: string, message: string): void {
    for (const socket of this.ctx.getWebSockets(`trade:${tradeId}`)) {
      try {
        socket.send(message);
      } catch {
        // A stale hibernating socket is harmless; the next connection can recover by receipt.
      }
    }
  }

  webSocketClose(): void {
    // State is persisted; disconnects before commit are intentionally non-destructive.
  }
}

const database = (env: Env): DurableObjectStub<TradeDatabase> => env.TRADE_DB.getByName("global");

const authenticate = async (request: Request, env: Env): Promise<Profile> => {
  const token = tokenFrom(request);
  const user = token ? await database(env).authenticate(token) : null;
  if (!user) throw new Failure("unauthorized", 401);
  return user;
};

const forwarded = (request: Request, id: string): Request => {
  const headers = new Headers(request.headers);
  headers.set(actorHeader, id);
  return new Request(request, { headers });
};

async function handle(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const path = url.pathname;
  const db = database(env);
  if (path === "/v1/trainers/register" && request.method === "POST") {
    const input = await body(request);
    exact(input, ["trainerName", "agreementPublicKey", "token"]);
    return json(await db.register({
      trainerName: field(input, "trainerName", 2, 20),
      agreementPublicKey: field(input, "agreementPublicKey", 80, 140),
      token: field(input, "token", 32, 128),
    }), 201);
  }
  const user = await authenticate(request, env);
  if (path === "/v1/trainers/me" && request.method === "PATCH") {
    const input = await body(request);
    exact(input, ["trainerName"]);
    return json(await db.updateTrainer(user.id, { trainerName: field(input, "trainerName", 2, 20) }));
  }
  if (path === "/v1/friends" && request.method === "GET") return json(await db.friends(user.id));
  if (path === "/v1/friends/requests" && request.method === "GET") return json(await db.friends(user.id));
  if (path === "/v1/friends/requests" && request.method === "POST") {
    const input = await body(request);
    exact(input, ["friendCode"]);
    return json(await db.requestFriend(user.id, { friendCode: field(input, "friendCode", 4, 32) }), 201);
  }
  const friendAccept = path.match(/^\/v1\/friends\/requests\/([^/]+)\/accept$/u);
  if (friendAccept && request.method === "POST") return json(await db.acceptFriend(user.id, friendAccept[1]));
  if (path === "/v1/trades/invite" && request.method === "POST") {
    const input = await body(request);
    exact(input, ["friendCode"]);
    return json(await db.invite(user.id, { friendCode: field(input, "friendCode", 4, 32) }), 201);
  }
  if (path === "/v1/trades/invites" && request.method === "GET") return json({ invites: await db.invites(user.id) });
  const inviteAccept = path.match(/^\/v1\/trades\/invites\/([^/]+)\/accept$/u);
  if (inviteAccept && request.method === "POST") return json(await db.acceptInvite(user.id, inviteAccept[1]));
  const receipt = path.match(/^\/v1\/trades\/([^/]+)\/receipt$/u);
  if (receipt && request.method === "GET") return json(await db.receipt(user.id, receipt[1]));
  const ack = path.match(/^\/v1\/trades\/([^/]+)\/ack$/u);
  if (ack && request.method === "POST") {
    const input = await body(request);
    exact(input, ["manifestDigest"]);
    return json(await db.acknowledge(user.id, ack[1], field(input, "manifestDigest", 1, 128)));
  }
  const ws = path.match(/^\/v1\/trades\/([^/]+)\/ws$/u);
  if (ws && request.headers.get("upgrade")?.toLowerCase() === "websocket") return db.fetch(forwarded(request, user.id));
  throw new Failure("not_found", 404);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await handle(request, env);
    } catch (error) {
      console.error(JSON.stringify({ message: "trade request failed", code: error instanceof Failure ? error.code : "internal_error", path: new URL(request.url).pathname }));
      return errorResponse(error);
    }
  },
} satisfies ExportedHandler<Env>;
