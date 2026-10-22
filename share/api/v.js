// نَسَق — معاينة رابط الملف المنشور: تُعيد صفحة فيها اسم الملف والمعلم والمدرسة لواتساب، ثم تنقل الزائر للملف
const SB = "https://rddibqurdjmrvmlneqss.supabase.co";
const ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJkZGlicXVyZGptcnZtbG5lcXNzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIxNzMwMjgsImV4cCI6MjEwNzc0OTAyOH0.AEyFYtwsFHGM3CyhSV13pSN420Hno5QMwxx6veetxXo"; // مفتاح عام (anon) — يُستخدم في صفحة التطبيق أصلًا
const APP = "https://k4044s-tech.github.io/haqibat-almalafat/";
const OG_IMG = APP + "og.png";
const esc = s => String(s || "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
module.exports = async (req, res) => {
  const id = String((req.query && req.query.id) || "").replace(/[^A-Za-z0-9]/g, "").slice(0, 16);
  const dest = APP + "?v=" + id;
  const ua = String((req.headers && req.headers["user-agent"]) || "");
  const bot = /facebookexternalhit|facebot|whatsapp|twitterbot|telegrambot|slackbot|linkedinbot|discordbot|skypeuripreview|googlebot|bingbot|applebot|embedly|pinterest|vkshare|redditbot/i.test(ua);
  const self = "https://" + String((req.headers && req.headers.host) || "") + "/v/" + id;
  let m = null;
  if (id.length >= 8) {
    try {
      const r = await fetch(SB + "/rest/v1/rpc/get_published_meta", {
        method: "POST",
        headers: { apikey: ANON, Authorization: "Bearer " + ANON, "Content-Type": "application/json" },
        body: JSON.stringify({ p_id: id }),
      });
      if (r.ok) m = await r.json();
    } catch (e) { m = null; }
  }
  const title = m && m.title ? m.title : "ملف إلكتروني — نَسَق";
  const who = m ? [m.owner, m.job].filter(Boolean).join(" — ") : "";
  const desc = m ? [who && "👤 " + who, m.school && "🏫 " + m.school, m.year && "📅 " + m.year].filter(Boolean).join("  ·  ") : "ملفات مدرسية منسّقة بهوية وزارة التعليم";
  const html = `<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)}${who ? " | " + esc(m.owner || "") : ""}</title>
<meta name="description" content="${esc(desc)}">
<meta property="og:type" content="article"><meta property="og:site_name" content="نَسَق"><meta property="og:locale" content="ar_SA">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:image" content="${OG_IMG}"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">
<meta property="og:url" content="${esc(self)}">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="${esc(title)}"><meta name="twitter:description" content="${esc(desc)}"><meta name="twitter:image" content="${OG_IMG}">
${bot ? "" : '<meta http-equiv="refresh" content="0;url=' + esc(dest) + '">'}
<style>body{font-family:Tahoma,Arial,sans-serif;background:#eef2f4;color:#15445a;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}a{color:#0b7f7c}</style>
</head><body><p>جارٍ فتح الملف… <a href="${esc(dest)}">اضغط هنا إن لم يُفتح</a></p>
${bot ? "" : "<script>location.replace(" + JSON.stringify(dest) + ")</script>"}</body></html>`;
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Cache-Control", "public, s-maxage=300, stale-while-revalidate=3600");
  res.status(200).send(html);
};
