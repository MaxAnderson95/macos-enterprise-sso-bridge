// The toolbar action must have a click listener registered for the button to be
// live in either engine. Starting a Handoff from that click arrives in a later
// ticket; today the listener exists so the skeleton is loadable and inert.
chrome.action.onClicked.addListener(() => {});
