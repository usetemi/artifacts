# Artifacts Domain Model

> This is the source of truth for the ubiquitous language, domain rules, and
> how Artifacts is supposed to work. It is a living goal-state document; code
> and tests show what is currently implemented and may lag behind it.

Artifacts is a place where people and coding agents build live web pages
together. An agent in any harness writes a page for the problem in front of
it — a board, a form, a dashboard, a spec — and publishes it to an
Organization. People and other agents open it, change it, and hand it back.
Every change to an Artifact's content is recorded, attributed, and kept, so
how people and agents shape each other's work can be studied later.

Core modeling themes:

1. **Humans and agents are peers on a page.** A person, a person's coding
   harness, and a coworker agent can each publish, change, submit, and wait
   on the same Artifact, and the record says which one did.
2. **The page is whatever the problem needs.** An Artifact's content is
   arbitrary HTML the author chose to build. Artifacts supplies hosting,
   shared state, and the hand-back loop; it prescribes no page shape.
3. **Every content change is kept.** Nothing that changed an Artifact's
   content is overwritten or deleted.
4. **Provider-agnostic.** Accounts are Artifacts accounts. No model vendor's
   account or harness is required, and every harness uses the same actions.

## 1. Ubiquitous Language

### 1.1 Identity and organizations

| Term | Meaning |
| --- | --- |
| **Instance** | One deployment of Artifacts, with its own accounts, Organizations, and Artifacts. An Instance may restrict sign-up to a set of email domains. Temi's Instance is usetemi.art, open to `@usetemi.com` addresses. |
| **User** | A person with an account on the Instance, signed in with Google. A User may belong to several Organizations. |
| **Organization** | The unit of ownership and sharing. Every Artifact belongs to exactly one Organization, and every Actor that can work on it is a member of that Organization or acts for one. |
| **Personal Organization** | The Organization created for a User at sign-up, with that User as its first member. It is an ordinary Organization under every rule; it differs only in being the default target for that User's publishes. |
| **Membership** | A User's belonging to an Organization. Every member has the same rights. |
| **Harness** | A User's coding tool — an MCP client such as Claude Code or Codex — connected with a named key that User issues, and shown as, for example, "Victor's Claude Code on kanto". A Harness acts as its User, with that User's rights. A User may have several Harnesses. |
| **Agent** | A coworker agent, such as Pidgey, that belongs to exactly one Organization and acts as itself, not as any person. A member of its Organization creates it and issues its keys. |
| **Actor** | Whoever performs an action: a User, a Harness (acting as its User), or an Agent. Every Event records its Actor. |
| **Viewer** | An Actor with an Artifact's page open. Only Actors in the Artifact's Organization can open it. |

### 1.2 Artifacts

| Term | Meaning |
| --- | --- |
| **Artifact** | One live page with a stable identity and URL: its Versions, its State, its Submissions, and its History. Created by an Actor in one Organization. |
| **Version** | One immutable HTML document published to an Artifact. Versions are numbered in order; the latest is the **current Version**, which the Artifact's URL serves. |
| **Publish** | Adding a new Version. An Actor publishes through the API or MCP; a page publishes itself through Self-Publish. |
| **Self-Publish** | A page replacing itself: the page's script publishes new HTML as the next Version, made by the Actor viewing the page. It is how a page acts as an editor for its own content. |
| **State** | An Artifact's shared JSON document, live for every Viewer and readable and writable by every Actor in the Artifact's Organization. It outlives Versions: a new Version sees the same State. |
| **State Change** | One batch of set and delete operations on State paths, applied together. |
| **Submission** | An Actor handing the page back, from the page or through the API or MCP: the State at that moment, an optional payload, the Version it was made on, and the Actor who made it. |
| **Wait** | An Actor receiving the Submissions made after a cursor it holds, as they arrive. Each waiter keeps its own cursor, so every waiter receives every Submission. |
| **Presence** | Who has the page open right now, with whatever each Viewer shares about itself. Ephemeral. |
| **Broadcast** | An ephemeral message from one Viewer's page to the others on the same Artifact. |
| **Archive** | The only removal: the Artifact leaves the Organization's list and refuses changes, and everything recorded about it stays readable. **Unarchive** reopens it. |
| **Page Runtime** | The script every page receives, through which it reads and changes State, shares Presence, sends Broadcasts, submits, and Self-Publishes. |
| **Chrome** | The frame around a page on the Instance's own origin: title, Version, Presence, and the Submit button. |
| **Content Origin** | The separate web origin where page HTML runs (usetemicontent.art for usetemi.art), holding no sign-in. |

### 1.3 The record

| Term | Meaning |
| --- | --- |
| **Event** | One recorded change to an Artifact's content: a Version Published, a State Changed, or a Submission Made. It records the Actor, the time, and what was changed. |
| **History** | An Artifact's Events in order, each readable with what it describes. |

## 2. Model

### 2.1 Entities and aggregates

| Entity | Identity | Responsibility and boundary |
| --- | --- | --- |
| **User** | User ID | Account, Memberships, Harnesses. |
| **Organization** | Organization ID | Name, Memberships, Agents; owns Artifacts. |
| **Harness** | Harness ID | One User's named coding tool and its key. |
| **Agent** | Agent ID | One Organization's coworker agent and its keys. |
| **Artifact** | Artifact ID (unguessable) | Versions, State, Submissions, Events, archive status. Every content change and its Event commit together. |

### 2.2 Domain services

| Domain service | Responsibility |
| --- | --- |
| **Sign-Up** | Admits a User whose verified email the Instance allows, and creates their Personal Organization in the same step, so no User exists without an Organization. |

### 2.3 Domain events

| Domain event | Meaning |
| --- | --- |
| **Version Published** | A new Version became current, by an Actor or by Self-Publish. |
| **State Changed** | One State Change was applied. |
| **Submission Made** | An Actor handed the page back. Waiters receive it. |

## 3. Rules and Invariants

### 3.1 Identity and organizations

- An Instance may restrict sign-up to verified emails in its allowed domains.
- Sign-up creates the User's Personal Organization with the User as its
  member.
- Any User may create further Organizations and becomes their first member.
- Managing access is done only by a User acting directly, never through a
  Harness or Agent: adding and removing members, creating Agents, and issuing
  and revoking keys.
- Any member adds an existing User to an Organization by email, and may remove
  a member; a User may leave. An Organization always keeps at least one
  member, so its last member can be neither removed nor leave. What a removed
  User did stays in the History, attributed to them.
- An Agent belongs to exactly one Organization and works on its Artifacts
  with a member's rights. Any member creates it and issues and revokes its
  keys.
- A Harness acts with exactly its User's rights, in every Organization that
  User belongs to. Its User issues and revokes its key.

### 3.2 Publishing and access

- Every Artifact belongs to exactly one Organization, fixed when it is
  created.
- A publish names its Organization. A User or Harness that names none
  publishes to the User's Personal Organization; an Agent always publishes to
  its own Organization. The Actor must be able to act in that Organization.
- Only Actors in an Artifact's Organization can see it. Every one of them may
  view it, change its State, submit, wait, publish a new Version, rename it,
  archive it, and unarchive it.

### 3.3 Closeout

- An archived Artifact refuses every content change. Its Versions, State,
  Submissions, and History stay readable to its Organization.
- Nothing is deleted. Archive is the only removal.

### 3.4 Content and the record

- A Version is stored exactly as published and never changes.
- A publish may state the Version it expects to replace; if another Version
  became current first, the publish is refused rather than silently
  overwriting. Self-Publish always states it.
- State is changed only through State Changes. Operations within one State
  Change apply together; across changes, the last write to a path wins.
- Every Version Published, State Changed, and Submission Made appends exactly
  one Event, committed together with the change. Events are never edited or
  deleted.
- Only content changes are Events. Title, archive, and unarchive
  changes are not.
- Presence and Broadcast are ephemeral and never recorded.
- A Submission is kept whether or not anyone is waiting. Every waiter
  receives every Submission after its own cursor.

### 3.5 Page trust

- Page HTML is authored by Actors and may be wrong or hostile. It runs only
  on the Content Origin and never with a Viewer's sign-in.
- A page can act only on its own Artifact, with the rights of the Viewer
  using it: it may read and change State, share Presence, Broadcast, submit,
  and Self-Publish.

## 4. Lifecycles and Processes

### 4.1 Artifact lifecycle

| Stage | Entry | What may happen next |
| --- | --- | --- |
| **Open** | Created by its first Publish. | Publish, Self-Publish, State Changes, Submissions, Waits, rename, Archive. |
| **Archived** | Archived by an Actor in its Organization. | Reading its Versions, State, Submissions, and History; Unarchive, returning it to Open. |

### 4.2 The hand-back loop

1. An Actor publishes an Artifact to an Organization and shares its URL.
2. The Actor waits for Submissions.
3. Viewers work on the page: its State changes live for everyone, and a page
   may Self-Publish a new Version.
4. An Actor on the page submits. Every waiter receives the Submission.
5. An Actor reads the Submission and the History, acts, and publishes the
   next Version; the loop repeats.
