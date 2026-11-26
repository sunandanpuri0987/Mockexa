from fastapi import APIRouter
from fastapi.responses import HTMLResponse


router = APIRouter(prefix="/legal", tags=["legal"])


def _page(title: str, body: str) -> HTMLResponse:
    return HTMLResponse(
        f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title} | Mockexa</title><style>
body{{font:16px/1.6 -apple-system,BlinkMacSystemFont,sans-serif;max-width:820px;margin:40px auto;padding:0 20px;color:#17233d}}
h1,h2{{line-height:1.25}}a{{color:#3157d5}}.muted{{color:#667085}}
</style></head><body><h1>{title}</h1><p class="muted">Effective: 27 November 2026</p>{body}
<hr><p>Questions or privacy requests: <a href="mailto:sunandanpuri0987@gmail.com">sunandanpuri0987@gmail.com</a></p></body></html>"""
    )


@router.get("/privacy", response_class=HTMLResponse)
def privacy_policy():
    return _page("Privacy Policy", """
<p>Mockexa provides interview preparation, aptitude practice, group discussion practice, company-specific preparation and resume tools.</p>
<h2>Information we process</h2><p>We process account identifiers and contact details, profile and target-role preferences, practice answers and transcripts, scores and feedback, resume content you choose to save, and limited technical logs needed for security and reliability.</p>
<h2>How we use information</h2><p>We use this information to authenticate you, personalize questions, generate feedback, synchronize progress and resumes, prevent abuse, diagnose failures and improve the service.</p>
<h2>Service providers</h2><p>Mockexa uses Supabase for authentication and data storage, Render for backend hosting, Google Gemini for selected AI-generated questions or feedback, and ElevenLabs for optional text-to-speech. Data is sent only when required for the feature you use.</p>
<h2>Retention and deletion</h2><p>Your cloud data is retained while your account is active. You can permanently delete your account and associated cloud data from Profile → Account Settings. Device-local data can be erased separately. Operational backups may persist temporarily according to infrastructure-provider retention schedules.</p>
<h2>Your choices</h2><p>You can edit profile data, avoid optional voice features, erase local data, sign out, or permanently delete your account. Do not include confidential or third-party personal information in practice answers or resumes.</p>
<h2>Security and children</h2><p>We use encrypted HTTPS transport and account-scoped access controls. No system is perfectly secure. Mockexa is not directed to children under 13.</p>
<h2>Changes</h2><p>Material changes will be reflected by updating the effective date and the in-app policy.</p>
""")


@router.get("/terms", response_class=HTMLResponse)
def terms_of_use():
    return _page("Terms of Use", """
<p>By using Mockexa, you agree to these terms. If you do not agree, do not use the service.</p>
<h2>Purpose</h2><p>Mockexa is an educational interview-preparation tool. It does not guarantee employment, interview outcomes, score accuracy or acceptance by any company.</p>
<h2>Your responsibilities</h2><p>Provide accurate account information, protect your sign-in credentials, use the service lawfully, and do not submit confidential employer material, malicious content, or personal information you do not have permission to use.</p>
<h2>AI-generated content</h2><p>Questions, ratings and feedback may be generated or assisted by AI and can be incomplete or incorrect. Review important guidance independently. Do not rely on Mockexa as legal, medical, financial or employment advice.</p>
<h2>Availability and acceptable use</h2><p>Features may change or be interrupted. You may not attempt unauthorized access, scrape at harmful volume, reverse engineer protected services, or interfere with other users.</p>
<h2>Your content</h2><p>You retain ownership of content you submit. You grant Mockexa permission to process it only as needed to provide and secure the service.</p>
<h2>Termination and deletion</h2><p>You may stop using Mockexa or delete your account at any time. We may suspend abusive or unlawful use. Account deletion is permanent.</p>
<h2>Liability</h2><p>To the maximum extent allowed by law, Mockexa is provided “as is” without warranties and is not liable for indirect or consequential losses arising from use of the service.</p>
""")
