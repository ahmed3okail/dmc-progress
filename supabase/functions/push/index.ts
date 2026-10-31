// DMC Progress ERP — Edge Function "push"
// Called by the database trigger push_notify() (header x-hook-secret) for:
//   progress_updates (submitted / endorsed / returned / approved), notifications, chat_messages, weekly_reports (insert)
// and by a signed-in user (Authorization: Bearer <jwt>, body {test:true}) to send a test to their own devices.
// Keys come from private.push_config through rpc push_config_get() (service role) — nothing secret in this file.
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

type Cfg = { hook_secret: string; vapid_public: string; vapid_private: string; vapid_subject: string };
let cfg: Cfg | null = null;
async function getCfg(): Promise<Cfg> {
  if (cfg) return cfg;
  const { data, error } = await sb.rpc("push_config_get");
  if (error) throw error;
  const c = (Array.isArray(data) ? data[0] : data) as Cfg;
  webpush.setVapidDetails(c.vapid_subject, c.vapid_public, c.vapid_private);
  return (cfg = c);
}

type Prof = { id: string; full_name: string | null; role: string; discipline: string | null; active: boolean | null; lang: string | null };
type Msg = { ar: { title: string; body: string }; en: { title: string; body: string }; tag: string; url?: string };

const DISC: Record<string, [string, string]> = {
  CIV: ["المهندس المدني", "Civil Engineer"], ARC: ["المهندس المعماري", "Architectural Engineer"],
  MEC: ["مهندس الميكانيكا", "Mechanical Engineer"], ELE: ["مهندس الكهرباء", "Electrical Engineer"],
};
const nameOf = (p?: Prof | null) => (p?.full_name || "").replace("@dmc.local", "") || "—";

async function profiles(filter: (q: any) => any = (q) => q): Promise<Prof[]> {
  const { data } = await filter(sb.from("profiles").select("id,full_name,role,discipline,active,lang"));
  return ((data || []) as Prof[]).filter((p) => p.active !== false);
}
async function membersOf(projectIds: string[]): Promise<Set<string>> {
  if (!projectIds.length) return new Set();
  const { data } = await sb.from("project_members").select("user_id").in("project_id", projectIds);
  return new Set((data || []).map((r: any) => r.user_id));
}
async function activity(id: string) {
  const { data } = await sb.from("activities").select("id,project_id,code,name,name_ar").eq("id", id).maybeSingle();
  return data as { id: string; project_id: string; code: string; name: string; name_ar: string | null } | null;
}
async function projectCode(id: string) {
  const { data } = await sb.from("projects").select("code").eq("id", id).maybeSingle();
  return (data as any)?.code || id;
}
async function requireCm() {
  const { data } = await sb.from("app_settings").select("value").eq("key", "require_cm").maybeSingle();
  return (data as any)?.value !== false;
}
// Site engineers of a discipline on the given projects (falls back to the whole discipline if nobody is a member)
async function engineers(disc: string | null, projectIds: string[], byUser?: string | null): Promise<Prof[]> {
  if (byUser) {
    const p = await profiles((q) => q.eq("id", byUser));
    if (p.length && p[0].role === "site") return p;
  }
  if (!disc) return [];
  const all = await profiles((q) => q.eq("role", "site").eq("discipline", disc));
  const mem = await membersOf(projectIds);
  const onProj = all.filter((p) => mem.has(p.id));
  return onProj.length ? onProj : all;
}

async function forUpdate(type: string, rec: any, old: any): Promise<[Prof[], Msg] | null> {
  const st = rec.status, was = old?.status;
  if (type === "UPDATE" && st === was) return null;
  if (type === "INSERT" && (st !== "submitted" || rec.source === "demo")) return null;
  const a = await activity(rec.activity_id);
  if (!a) return null;
  const code = await projectCode(a.project_id);
  const act = `${a.code} · ${code}`, nAr = a.name_ar || a.name, nEn = a.name;
  const [dAr, dEn] = DISC[rec.discipline] || [rec.discipline || "", rec.discipline || ""];
  const pct = rec.pct == null ? "" : ` ${rec.pct}%`;
  if (st === "submitted") {
    const cm = await requireCm();
    let to: Prof[];
    if (cm) {
      const cms = await profiles((q) => q.eq("role", "cm"));
      const mem = await membersOf([a.project_id]);
      to = cms.filter((p) => mem.has(p.id));
      if (!to.length) to = cms;
    } else to = await profiles((q) => q.eq("role", "planner"));
    if (was === "endorsed") {
      const why = rec.review_comment || "";
      return [to, {
        ar: { title: `مرتجع من التخطيط — ${act}`, body: `${nAr}${why ? " — " + why : ""}` },
        en: { title: `Returned by Planning — ${act}`, body: `${nEn}${why ? " — " + why : ""}` }, tag: `pu-${rec.id}`,
      }];
    }
    return [to, {
      ar: { title: `تحديث جديد للمراجعة — ${act}`, body: `${dAr} بعت${pct}: ${nAr}` },
      en: { title: `New update to review — ${act}`, body: `${dEn} submitted${pct}: ${nEn}` }, tag: `pu-${rec.id}`,
    }];
  }
  if (st === "endorsed") {
    const to = await profiles((q) => q.eq("role", "planner"));
    return [to, {
      ar: { title: `معتمد من مدير التنفيذ — ${act}`, body: `في انتظار موافقتك${pct}: ${nAr}` },
      en: { title: `Endorsed by CM — ${act}`, body: `Awaiting your approval${pct}: ${nEn}` }, tag: `pu-${rec.id}`,
    }];
  }
  const to = await engineers(rec.discipline, [a.project_id], rec.by_user);
  if (st === "returned") {
    const why = rec.review_comment || rec.cm_comment || "";
    return [to, {
      ar: { title: `تحديث مرتجع — ${act}`, body: `${nAr}${why ? " — " + why : ""}` },
      en: { title: `Update returned — ${act}`, body: `${nEn}${why ? " — " + why : ""}` }, tag: `pu-${rec.id}`,
    }];
  }
  if (st === "approved") {
    return [to, {
      ar: { title: `تمت الموافقة ✓ — ${act}`, body: `${nAr}${pct}` },
      en: { title: `Approved ✓ — ${act}`, body: `${nEn}${pct}` }, tag: `pu-${rec.id}`,
    }];
  }
  return null;
}

async function forNotification(rec: any): Promise<[Prof[], Msg] | null> {
  if (String(rec.id || "").startsWith("R_seed")) return null;
  const ids: string[] = rec.activity_ids || [];
  let projects: string[] = [];
  if (ids.length) {
    const { data } = await sb.from("activities").select("project_id").in("id", ids);
    projects = [...new Set((data || []).map((r: any) => r.project_id))];
  }
  const to = await engineers(rec.to_discipline, projects);
  const note = rec.note || "";
  if (rec.type === "adjusted") {
    return [to, {
      ar: { title: "مدير التنفيذ عدّل تحديثك", body: `${rec.from_pct ?? ""}% ← ${rec.to_pct ?? ""}%${note ? " — " + note : ""}` },
      en: { title: "CM adjusted your update", body: `${rec.from_pct ?? ""}% → ${rec.to_pct ?? ""}%${note ? " — " + note : ""}` }, tag: `n-${rec.id}`,
    }];
  }
  return [to, {
    ar: { title: "تذكير: حدّث أنشطتك", body: note || `${ids.length} نشاط محتاج تحديث` },
    en: { title: "Reminder: update your activities", body: note || `${ids.length} activities need an update` }, tag: `n-${rec.id}`,
  }];
}

async function forChat(rec: any): Promise<[Prof[], Msg] | null> {
  const room: string = rec.room || "";
  const sender = (await profiles((q) => q.eq("id", rec.sender)))[0];
  let to: Prof[] = [];
  let roomAr = "", roomEn = "";
  if (room === "general") {
    to = await profiles();
    roomAr = "المجموعة العامة"; roomEn = "General";
  } else if (room.startsWith("proj:")) {
    const pid = room.slice(5);
    const mem = await membersOf([pid]);
    to = (await profiles()).filter((p) => ["admin", "pm", "planner"].includes(p.role) || mem.has(p.id));
    roomAr = roomEn = await projectCode(pid);
  } else if (room.startsWith("dm:")) {
    const ids = room.slice(3).split(":");
    to = await profiles((q) => q.in("id", ids));
  }
  to = to.filter((p) => p.id !== rec.sender);
  const who = nameOf(sender);
  const body = (rec.body || "").slice(0, 180) || (rec.has_image ? "📷" : "");
  return [to, {
    ar: { title: roomAr ? `${who} · ${roomAr}` : who, body: body || "📷 صورة" },
    en: { title: roomEn ? `${who} · ${roomEn}` : who, body: body || "📷 Photo" },
    tag: `chat-${room}`, url: "#chat",
  }];
}

async function forReport(rec: any): Promise<[Prof[], Msg] | null> {
  const sentTo: string[] = rec.sent_to || [];
  const roles = sentTo.filter((r) => r === "cm" || r === "pm");
  if (!roles.length) return null;
  let to = await profiles((q) => q.in("role", roles));
  if (rec.project_id && roles.includes("cm")) {
    const mem = await membersOf([rec.project_id]);
    to = to.filter((p) => p.role !== "cm" || mem.has(p.id));
  }
  const proj = rec.project_id ? await projectCode(rec.project_id) : "";
  const no = rec.report_no || "";
  return [to, {
    ar: { title: `تقرير أسبوعي جديد${proj ? " — " + proj : ""}`, body: `${no}${rec.note ? " — " + rec.note : ""}` },
    en: { title: `New weekly report${proj ? " — " + proj : ""}`, body: `${no}${rec.note ? " — " + rec.note : ""}` },
    tag: `wr-${rec.id}`,
  }];
}

async function send(to: Prof[], msg: Msg) {
  if (!to.length) return { users: 0, sent: 0 };
  const ids = [...new Set(to.map((p) => p.id))];
  const lang = new Map(to.map((p) => [p.id, p.lang === "en" ? "en" : "ar"]));
  const { data: subs } = await sb.from("push_subscriptions").select("endpoint,user_id,p256dh,auth").in("user_id", ids);
  let sent = 0;
  await Promise.all((subs || []).map(async (s: any) => {
    const m = msg[lang.get(s.user_id) as "ar" | "en"] || msg.ar;
    const payload = JSON.stringify({ title: m.title, body: m.body, tag: msg.tag, url: msg.url || "", lang: lang.get(s.user_id) });
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 86400, urgency: "high" });
      sent++;
    } catch (e: any) {
      if (e?.statusCode === 404 || e?.statusCode === 410) await sb.from("push_subscriptions").delete().eq("endpoint", s.endpoint);
      else console.error("push failed", e?.statusCode, e?.body || e?.message);
    }
  }));
  return { users: ids.length, devices: (subs || []).length, sent };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method" }, 405);
  try {
    const c = await getCfg();
    const body = await req.json().catch(() => ({}));
    // A signed-in user asking for a test on their own devices
    if (body?.test) {
      const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
      const { data: u } = await sb.auth.getUser(token);
      if (!u?.user) return json({ error: "unauthorized" }, 401);
      const me = await profiles((q) => q.eq("id", u.user!.id));
      if (!me.length) return json({ error: "no profile" }, 403);
      const r = await send(me, {
        ar: { title: "DMC Progress ✓", body: "الإشعارات شغالة على الجهاز ده." },
        en: { title: "DMC Progress ✓", body: "Notifications work on this device." }, tag: "test",
      });
      return json(r);
    }
    if (req.headers.get("x-hook-secret") !== c.hook_secret) return json({ error: "unauthorized" }, 401);
    const { table, type, record, old_record } = body;
    let r: [Prof[], Msg] | null = null;
    if (table === "progress_updates") r = await forUpdate(type, record, old_record);
    else if (table === "notifications") r = await forNotification(record);
    else if (table === "chat_messages") r = await forChat(record);
    else if (table === "weekly_reports") r = await forReport(record);
    if (!r) return json({ skipped: true });
    return json(await send(r[0], r[1]));
  } catch (e: any) {
    console.error(e);
    return json({ error: String(e?.message || e) }, 500);
  }
});
