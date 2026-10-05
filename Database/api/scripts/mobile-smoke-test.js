const apiBaseUrl = (process.env.API_BASE_URL || "http://localhost:3000/api").replace(/\/+$/, "");
const password = process.env.SMOKE_PASSWORD || "FitConnect1!";
const suffix = new Date().toISOString().replace(/\D/g, "").slice(0, 14);
const keepContent = process.env.SMOKE_DELETE_CONTENT !== "1";

const tinyPng =
  "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=";

const userA = {
  username: `mobile_smoke_a_${suffix}`,
  email: `mobile_smoke_a_${suffix}@fitconnect.local`,
  password,
};

const userB = {
  username: `mobile_smoke_b_${suffix}`,
  email: `mobile_smoke_b_${suffix}@fitconnect.local`,
  password,
};

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function request(method, path, { token, body, expected = [200] } = {}) {
  const response = await fetch(`${apiBaseUrl}${path}`, {
    method,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

  const rawText = await response.text();
  let data = null;
  if (rawText) {
    try {
      data = JSON.parse(rawText);
    } catch {
      data = rawText;
    }
  }

  if (!expected.includes(response.status)) {
    throw new Error(
      `${method} ${path} -> ${response.status}. Respuesta: ${rawText}`,
    );
  }

  return data;
}

async function registerAndLogin(user) {
  await request("POST", "/auth/register", {
    expected: [201],
    body: user,
  });

  const login = await request("POST", "/auth/login", {
    body: {
      username: user.username,
      password: user.password,
    },
  });

  assert(login.token, `Login sin token para ${user.username}`);
  return login.token;
}

async function main() {
  console.log(`API: ${apiBaseUrl}`);
  await request("GET", "/health");
  console.log("OK health");

  const tokenA = await registerAndLogin(userA);
  const tokenB = await registerAndLogin(userB);
  console.log("OK registro y login de dos usuarios");

  const users = await request("GET", "/social/users", { token: tokenA });
  assert(
    Array.isArray(users) && users.some((user) => user.username === userB.username),
    "El usuario B no aparece en el listado visto por usuario A",
  );
  console.log("OK usuarios compartidos");

  await request("PUT", "/social/profile", {
    token: tokenA,
    body: {
      name: "Mobile Smoke A",
      bio: "Perfil creado por la prueba movil",
      sport: "Gimnasio",
    },
  });

  const postText = `Post compartido desde prueba movil ${suffix}`;
  const createdPost = await request("POST", "/social/posts", {
    token: tokenA,
    expected: [201],
    body: {
      content: postText,
      imageData: tinyPng,
    },
  });

  const postId = createdPost.post?.id;
  assert(postId, "La API no devolvio id del post creado");
  assert(
    typeof createdPost.post?.image === "string" &&
      createdPost.post.image.startsWith("/uploads/posts/"),
    "El post con imagen no se guardo como archivo en /uploads/posts",
  );
  console.log(`OK post con imagen creado: ${postId}`);

  await request("POST", `/social/follow/user/${encodeURIComponent(userA.username)}`, {
    token: tokenB,
  });

  const profileAFromB = await request(
    "GET",
    `/social/profile/user/${encodeURIComponent(userA.username)}`,
    { token: tokenB },
  );
  assert(profileAFromB.isFollowing === true, "El usuario B no sigue al usuario A");
  assert(profileAFromB.followersCount >= 1, "El contador de seguidores no subio");
  assert(profileAFromB.postsCount >= 1, "El contador de posts no refleja el post creado");
  console.log("OK follow y perfil compartido");

  const feedB = await request("GET", "/social/posts", { token: tokenB });
  assert(
    Array.isArray(feedB) && feedB.some((post) => Number(post.id) === Number(postId)),
    "El post del usuario A no aparece en el feed del usuario B",
  );
  console.log("OK feed compartido entre usuarios");

  await request("POST", `/social/posts/${postId}/like`, { token: tokenB });

  const commentText = `Comentario desde usuario B ${suffix}`;
  await request("POST", `/social/posts/${postId}/comment`, {
    token: tokenB,
    expected: [201],
    body: { content: commentText },
  });

  const comments = await request("GET", `/social/posts/${postId}/comments`, {
    token: tokenA,
  });
  assert(
    Array.isArray(comments) &&
      comments.some((comment) => comment.content === commentText),
    "El comentario del usuario B no aparece para usuario A",
  );

  const feedA = await request("GET", "/social/posts", { token: tokenA });
  const postFromA = feedA.find((post) => Number(post.id) === Number(postId));
  assert(postFromA && postFromA.likesCount >= 1, "El like no se refleja en el feed");
  console.log("OK likes y comentarios compartidos");

  const story = await request("POST", "/social/stories", {
    token: tokenA,
    expected: [201],
    body: { imageData: tinyPng },
  });
  const storyId = story.story?.id;
  assert(storyId, "La API no devolvio id de historia");

  const storiesB = await request("GET", "/social/stories", { token: tokenB });
  assert(
    Array.isArray(storiesB) &&
      storiesB.some((item) => Number(item.id) === Number(storyId)),
    "La historia del usuario A no aparece para usuario B",
  );
  console.log(`OK historias compartidas: ${storyId}`);

  const messageText = `Mensaje de prueba movil ${suffix}`;
  await request("POST", `/social/messages/user/${encodeURIComponent(userA.username)}`, {
    token: tokenB,
    expected: [201],
    body: { content: messageText },
  });

  const messagesForA = await request(
    "GET",
    `/social/messages/user/${encodeURIComponent(userB.username)}`,
    { token: tokenA },
  );
  assert(
    Array.isArray(messagesForA) &&
      messagesForA.some((message) => message.content === messageText),
    "El mensaje entre usuarios no se comparte correctamente",
  );
  console.log("OK mensajes compartidos");

  if (!keepContent) {
    await request("DELETE", `/social/stories/${storyId}`, { token: tokenA });
    await request("DELETE", `/social/posts/${postId}`, { token: tokenA });
    console.log("OK contenido de prueba borrado");
  }

  console.log("");
  console.log("Prueba movil completada correctamente.");
  console.log(`Usuario A: ${userA.username}`);
  console.log(`Usuario B: ${userB.username}`);
  console.log(`Password: ${password}`);
  if (keepContent) {
    console.log("El post y la historia se han dejado en la base de datos para verlos en la app.");
  }
}

main().catch((error) => {
  console.error("");
  console.error("Prueba movil fallida:");
  console.error(error.message);
  process.exit(1);
});
