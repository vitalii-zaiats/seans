/**
 * The one question first run asks, and the fact that it has been asked.
 *
 * The television's wizard opens with the same one, and puts it first for the
 * same reason: it is the only question here whose answer this app cannot guess,
 * and until it is answered there is nothing honest to tell the server.
 * Everything else that wizard settles — which sections to carry, which channel
 * sources — is a property of a box, and a browser has none of it.
 *
 * The answer is kept next to the two lists, in this browser, because that is
 * the whole of what it decides.
 */

export type WelcomeChoice = 'anonymous' | 'guest' | 'account'

const KEY = 'welcome.answered'

function read(): WelcomeChoice | null {
  if (!import.meta.client) return null
  try {
    const raw = window.localStorage.getItem(KEY)
    return raw === 'anonymous' || raw === 'guest' || raw === 'account' ? raw : null
  } catch {
    // A browser that refuses storage asks again every visit. That is the right
    // way for this to fail: the question is cheap, and the alternative is
    // deciding on somebody's behalf.
    return null
  }
}

export function useWelcome() {
  const answered = useState<WelcomeChoice | null>('welcome.answer', () => read())

  function answer(choice: WelcomeChoice): void {
    answered.value = choice
    try {
      window.localStorage.setItem(KEY, choice)
    } catch {
      // See above.
    }
  }

  /**
   * Forgets the answer, so the question is asked again.
   *
   * The dialog's own foot says this is possible; without it that line was a
   * promise nothing kept. It does not sign anybody out — a session and a
   * preference about one are different things.
   */
  function reset(): void {
    answered.value = null
    try {
      window.localStorage.removeItem(KEY)
    } catch {
      // Nothing was stored to begin with.
    }
  }

  return { answered, answer, reset }
}
