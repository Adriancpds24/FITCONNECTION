type EmailPayload = {
  to: string;
  subject: string;
  text: string;
  html: string;
};

const EMAIL_TIMEOUT_MS = Number(process.env.EMAIL_TIMEOUT_MS || 8000);

function parseFromAddress(input: string): { email: string; name?: string } {
  const trimmed = input.trim();
  const match = trimmed.match(/^(.+)\s<([^>]+)>$/);
  if (!match) return { email: trimmed };
  return { name: match[1].trim(), email: match[2].trim() };
}

async function sendWithBrevoApi(
  payload: EmailPayload,
  from: string,
): Promise<boolean> {
  const apiKey = process.env.BREVO_API_KEY?.trim();
  if (!apiKey) return false;

  const fromData = parseFromAddress(from);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), EMAIL_TIMEOUT_MS);
  let response: Response;

  try {
    response = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "api-key": apiKey,
      },
      body: JSON.stringify({
        sender: fromData.name
          ? { name: fromData.name, email: fromData.email }
          : { email: fromData.email },
        to: [{ email: payload.to }],
        subject: payload.subject,
        htmlContent: payload.html,
        textContent: payload.text,
      }),
      signal: controller.signal,
    });
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") {
      throw new Error(`Brevo API timeout after ${EMAIL_TIMEOUT_MS}ms`);
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }

  if (!response.ok) {
    const details = await response.text().catch(() => "");
    throw new Error(`Brevo API error (${response.status}): ${details}`);
  }

  return true;
}

function getTransporter() {
  const { SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS } = process.env;

  if (!SMTP_HOST || !SMTP_PORT || !SMTP_USER || !SMTP_PASS) {
    throw new Error(
      "SMTP no configurado. Define SMTP_HOST, SMTP_PORT, SMTP_USER y SMTP_PASS.",
    );
  }

  let nodemailer: {
    createTransport: (config: unknown) => {
      sendMail: (message: unknown) => Promise<unknown>;
    };
  };

  try {
    nodemailer = require("nodemailer");
  } catch (error) {
    throw new Error(
      "Falta la dependencia nodemailer. Ejecuta npm install en Database/api.",
    );
  }

  const secure = process.env.SMTP_SECURE === "true" || Number(SMTP_PORT) === 465;

  return nodemailer.createTransport({
    host: SMTP_HOST,
    port: Number(SMTP_PORT),
    secure,
    connectionTimeout: EMAIL_TIMEOUT_MS,
    greetingTimeout: EMAIL_TIMEOUT_MS,
    socketTimeout: EMAIL_TIMEOUT_MS,
    auth: {
      user: SMTP_USER,
      pass: SMTP_PASS,
    },
  });
}

export async function sendEmail(payload: EmailPayload): Promise<void> {
  const from = process.env.SMTP_FROM || process.env.SMTP_USER;

  if (!from) {
    throw new Error("SMTP_FROM no configurado.");
  }

  const sentWithBrevoApi = await sendWithBrevoApi(payload, from);
  if (sentWithBrevoApi) {
    return;
  }

  const transporter = getTransporter();

  await transporter.sendMail({
    from,
    to: payload.to,
    subject: payload.subject,
    text: payload.text,
    html: payload.html,
  });
}
