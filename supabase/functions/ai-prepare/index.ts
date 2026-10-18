// نَسَق — دالة التجهيز الذكي (Supabase Edge Function)
// تتحقق من صلاحية المستخدم وعدد مرات الاستخدام، ثم تطلب من Claude تعبئة الملف.
// مفتاح Anthropic يُحفظ سرًّا: supabase secrets set ANTHROPIC_API_KEY=...
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const j = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

// الأسعار بالدولار لكل مليون توكن (للتسجيل في لوحة المشرف)
const PRICE: Record<string, [number, number]> = {
  "claude-sonnet-5-5": [2, 10],
  "claude-haiku-5-5": [0.1, 0.5],
  "claude-opus-5-5": [4, 20],
};
async function callClaude(KEY: string, model: string, content: unknown[], max: number, system?: string) {
  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({ model, max_tokens: max, ...(system ? { system } : {}), messages: [{ role: "user", content }] }),
  });
  const out = await r.json();
  const text = r.ok ? (out.content || []).filter((c: { type: string }) => c.type === "text").map((c: { text: string }) => c.text).join("") : "";
  return { ok: r.ok, status: r.status, err: out?.error?.message, text, it: out.usage?.input_tokens || 0, ot: out.usage?.output_tokens || 0 };
}
const JOB_TTL_MIN = 40;   // مدة صلاحية العملية لإرسال بقية الأجزاء
const MAX_PARTS = 24;
const MAX_IMAGES = 12;
const MAX_IMG_B64 = 450_000;
const MAX_FIELDS = 400;
const MAX_DOC_IMGS = 40; // صفحات مصوّرة من الملفات المرجعية (تُصغَّر على جهاز المستخدم)
const MAX_DOC_TEXT = 120_000;

const DIGEST = `فيما سبق ملفات مرجعية لمدرسة (تقارير تقويم مدرسي، بطاقات نافس، تقارير تقويم ذاتي، أو ما شابه)؛ بعض الصفحات نص مستخرج آليًا وبعضها صور للصفحات. لخّص كل ملف تحت عنوان باسمه، واستخرج ملخصًا عربيًا دقيقًا منظمًا يُستخدم لاحقًا في إعداد خطط المدرسة وملفاتها:
- بيانات المدرسة الأساسية (الاسم، المرحلة، الجنس، الإدارة، العام) إن وُجدت.
- النتائج حسب كل مجال ومعيار ومؤشر مع المستوى أو التقدير أو النسبة كما هي حرفيًا.
- نتائج نافس لكل صف ومادة ومجال: نسبة الإتقان، والمتوسط، ومقدار التغير، والمقارنة بالمستويات الأعلى إن وُجدت.
- أعلى المؤشرات أداءً (نقاط القوة) وأدناها (فرص التحسين) مرتبة.
- التوصيات الواردة في الملف.
قواعد: انقل الأرقام والنسب كما هي دون تقريب أو تخمين، ولا تذكر أسماء الطلاب، ولا تضف شيئًا غير موجود في الملف. عند تعارض النص المستخرج مع صورة الصفحة اعتمد الصورة. اكتب نقاطًا مختصرة لا تتجاوز 700 كلمة لكل ملف.`;

const SYSTEM = `أنت «مجهّز نَسَق»: خبير في إعداد الملفات المدرسية الرسمية لوزارة التعليم في المملكة العربية السعودية (ملفات شواهد الأداء الوظيفي، الخطط، السجلات، ملفات الإدارة والطلاب).
مهمتك تعبئة خانات ملف واحد بصياغة عربية فصحى رسمية واضحة ومختصرة، مناسبة لمادة المستخدم ومرحلته وبياناته.
قواعد صارمة:
- لا تخترع حقائق محددة لم يذكرها المستخدم: لا أسماء أشخاص، ولا تواريخ، ولا أرقام أو نسب أو نتائج، ولا أسماء جهات. اترك هذه الخانات فارغة ("").
- إذا وُجد «ملخص الملفات المرجعية» فهو بيانات حقيقية من تقارير المدرسة الرسمية: استخدم أرقامه ونسبه ومستوياته كما هي تمامًا في التشخيص والمؤشر الحالي والمستهدف ونقاط القوة والضعف، وابنِ الأهداف والإجراءات على أدنى المؤشرات فيه.
- اكتب الصياغات العامة (المقدمات، الأهداف، الإجراءات، الأساليب، التوصيات، وصف الشواهد) بناءً على وصف المستخدم لعمله.
- في الجداول: عبّئ الصفوف التي لها معنى عام (أهداف، برامج، إجراءات، استراتيجيات) بحد أقصى 6 صفوف لكل جدول، واترك سجلات المتابعة والحضور والدرجات فارغة.
- الخانة القصيرة (خلية جدول) جملة قصيرة أو بضع كلمات. الخانة الطويلة (فقرة) من 2 إلى 6 أسطر، واستخدم الترقيم "١. ٢. ٣." عند التعداد مع فصل الأسطر بـ \\n.
- إذا وُجد في البيانات «ما نفّذه المستخدم في عناصر الملف» فاكتب شواهد ونصوص كل عنصر بناءً على ما اختاره فقط، وصِغ كل بند مختار صياغة رسمية مع وصف موجز لطريقة تنفيذه. أما العناصر التي لم يحدد فيها شيئًا فاترك خاناتها فارغة ولا تدّعِ أنه نفّذ فيها شيئًا.
- التزم بأسلوب الكتابة المطلوب (مختصر / متوسط / مفصّل) وبالمادة والمرحلة المحددتين، واستخدم مصطلحات وزارة التعليم (منصة مدرستي، نظام نور، نواتج التعلم، مجتمعات التعلم المهنية…).
- لا تغيّر الخانات التي فيها نص إلا إذا طُلب الاستبدال.
- عند توزيع الصور: ضع كل صورة في الخانة الأنسب لمحتواها من قائمة خانات الشواهد، واكتب لها وصفًا قصيرًا (3-8 كلمات). لا تضع صورتين في خانة واحدة.
- أعد JSON فقط بدون أي نص قبله أو بعده، بالشكل: {"fills":{"المفتاح":"النص"},"images":[{"i":0,"slot":"مفتاح الخانة","cap":"الوصف"}]}`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return j({ error: "method" }, 405);
  try {
    const KEY = Deno.env.get("ANTHROPIC_API_KEY");
    if (!KEY) return j({ error: "not_configured" }, 503);
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    const { data: ud } = await sb.auth.getUser(token);
    const user = ud?.user;
    if (!user) return j({ error: "auth" }, 401);

    const body = await req.json();
    const file = String(body.file || "").slice(0, 60);
    if (!file) return j({ error: "bad_request" }, 400);

    const { data: prof } = await sb.from("profiles").select("role,status,perms").eq("id", user.id).single();
    const isAdmin = prof?.role === "admin";
    const perms = (prof?.perms || {}) as Record<string, Record<string, unknown>>;
    const allowed = isAdmin || (prof?.status === "active" && !!(perms.all?.ai || perms[file]?.ai));
    if (!allowed) return j({ error: "no_permission" }, 403);

    const { data: st } = await sb.from("settings").select("value").eq("key", "ai").maybeSingle();
    const cfg = (st?.value || {}) as { limit?: number; model?: string; enabled?: boolean };
    if (cfg.enabled === false && !isAdmin) return j({ error: "disabled" }, 403);
    const limit = Number(cfg.limit ?? 3);
    const model = String(cfg.model || "claude-sonnet-5-5");

    // بدء عملية جديدة أو متابعة عملية قائمة
    let job: { id: number; parts: number; input_tokens: number; output_tokens: number; cost_usd: number } | null = null;
    if (body.job) {
      const since = new Date(Date.now() - JOB_TTL_MIN * 60_000).toISOString();
      const { data } = await sb.from("ai_jobs").select("id,parts,input_tokens,output_tokens,cost_usd")
        .eq("id", body.job).eq("uid", user.id).eq("file_id", file).eq("status", "running").gte("created_at", since).maybeSingle();
      if (!data) return j({ error: "job_expired" }, 409);
      if (data.parts >= MAX_PARTS) return j({ error: "too_many_parts" }, 429);
      job = data;
    } else {
      const { count } = await sb.from("ai_jobs").select("id", { count: "exact", head: true })
        .eq("uid", user.id).eq("file_id", file).neq("status", "failed");
      if (!isAdmin && (count || 0) >= limit) return j({ error: "limit", limit }, 429);
      const { data, error } = await sb.from("ai_jobs").insert({ uid: user.id, file_id: file }).select("id,parts,input_tokens,output_tokens,cost_usd").single();
      if (error) throw error;
      job = data;
    }

    const bill = async (it: number, ot: number, last: boolean) => {
      const [pi, po] = PRICE[model] || PRICE["claude-sonnet-5-5"];
      const cost = (it * pi + ot * po) / 1e6;
      await sb.from("ai_jobs").update({
        parts: job!.parts + 1, input_tokens: job!.input_tokens + it, output_tokens: job!.output_tokens + ot,
        cost_usd: Number(job!.cost_usd) + cost, status: last ? "done" : "running",
      }).eq("id", job!.id);
    };

    // قراءة ملف مرجعي (PDF) واستخراج ملخص بياناته
    if (body.mode === "digest") {
      const docs = (Array.isArray(body.docs) ? body.docs : []).slice(0, 6);
      const content: unknown[] = [];
      let imgN = 0, txtN = 0;
      for (const d of docs) {
        const name = String(d?.name || "ملف").slice(0, 120);
        content.push({ type: "text", text: `===== الملف: ${name} =====` });
        const t = String(d?.text || "").slice(0, Math.max(0, MAX_DOC_TEXT - txtN));
        txtN += t.length;
        if (t) content.push({ type: "text", text: t });
        for (const im of (Array.isArray(d?.imgs) ? d.imgs : [])) {
          if (imgN >= MAX_DOC_IMGS || typeof im !== "string" || im.length > MAX_IMG_B64) continue;
          imgN++;
          content.push({ type: "image", source: { type: "base64", media_type: "image/jpeg", data: im } });
        }
      }
      const fail = async (e: string, st: number, detail?: unknown) => {
        if (!job!.parts) await sb.from("ai_jobs").update({ status: "failed" }).eq("id", job!.id);
        return j({ error: e, detail, job: job!.parts ? job!.id : null }, st);
      };
      if (!txtN && !imgN) return fail("doc_unreadable", 400);
      content.push({ type: "text", text: DIGEST });
      const c = await callClaude(KEY, model, content, 6000);
      if (!c.ok) return fail(c.status === 400 ? "doc_unreadable" : "upstream", 502, c.err);
      await bill(c.it, c.ot, false);
      return j({ job: job.id, digest: c.text.slice(0, 16000) });
    }

    // التحقق من الحجم
    const fields = Array.isArray(body.fields) ? body.fields.slice(0, MAX_FIELDS) : [];
    const images = Array.isArray(body.images) ? body.images.slice(0, MAX_IMAGES).filter((x: string) => typeof x === "string" && x.length < MAX_IMG_B64) : [];
    const slots = Array.isArray(body.slots) ? body.slots.slice(0, 80) : [];
    const info = body.info || {};

    const content: unknown[] = [];
    images.forEach((b64: string, i: number) => {
      content.push({ type: "text", text: `صورة رقم ${i}:` });
      content.push({ type: "image", source: { type: "base64", media_type: "image/jpeg", data: b64 } });
    });
    content.push({
      type: "text",
      text: `الملف: ${String(body.title || "").slice(0, 200)}
بيانات المستخدم وما يقوله عن عمله:
${JSON.stringify(info).slice(0, 40000)}
استبدال النصوص الموجودة: ${body.replace ? "نعم" : "لا"}

خانات الشواهد المتاحة لتوزيع الصور (المفتاح، الصفحة):
${JSON.stringify(slots)}

الخانات المطلوب تعبئتها في هذا الجزء (k = المفتاح، p = الصفحة، l = التسمية أو رأس العمود، r = بداية الصف، v = النص الحالي، t = النوع: s قصير / l طويل):
${JSON.stringify(fields)}

${images.length ? "وزّع الصور على خانات الشواهد واكتب وصفها." : "لا توجد صور في هذا الجزء، أعد images: []."}
أعد JSON فقط.`,
    });

    const c = await callClaude(KEY, model, content, 12000, SYSTEM);
    if (!c.ok) {
      await sb.from("ai_jobs").update({ status: job.parts ? "running" : "failed" }).eq("id", job.id);
      return j({ error: "upstream", detail: c.err || c.status }, 502);
    }
    const m = c.text.replace(/```json|```/g, "").match(/\{[\s\S]*\}/);
    let parsed: { fills?: Record<string, string>; images?: unknown[] } = {};
    try { parsed = m ? JSON.parse(m[0]) : {}; } catch { parsed = {}; }
    await bill(c.it, c.ot, !!body.last);

    const { count: used } = await sb.from("ai_jobs").select("id", { count: "exact", head: true })
      .eq("uid", user.id).eq("file_id", file).neq("status", "failed");
    return j({ job: job.id, fills: parsed.fills || {}, images: parsed.images || [], used, limit: isAdmin ? null : limit });
  } catch (e) {
    return j({ error: "server", detail: String((e as Error)?.message || e) }, 500);
  }
});
