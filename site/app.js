"use strict";
const API = "/api/v1/organisations/lr";
const eventNode = document.getElementById("public-events");
async function loadPublicEvents() {
  if (!eventNode) return;
  try {
    const response = await fetch(API + "/events", {headers: {"Accept":"application/json"}});
    if (!response.ok) throw new Error("events unavailable");
    const body = await response.json();
    const published = body.events.filter(event => event.status === "published");
    eventNode.replaceChildren();
    if (!published.length) {
      const note = document.createElement("p");
      note.textContent = "No published chapter events at present. Check back for updates.";
      eventNode.append(note);
      return;
    }
    for (const event of published) {
      const card = document.createElement("article");
      card.className = "card";
      const title = document.createElement("h3");
      title.textContent = event.title;
      const date = document.createElement("p");
      date.className = "muted";
      date.textContent = new Date(event.starts_at).toLocaleString("en-GB",{dateStyle:"full",timeStyle:"short",timeZone:"Europe/London"});
      card.append(title, date);
      eventNode.append(card);
    }
  } catch {
    eventNode.textContent = "Chapter events are temporarily unavailable.";
  }
}
loadPublicEvents();
