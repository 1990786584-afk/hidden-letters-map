import { useState } from "react";
import { createRoot } from "react-dom/client";
import LettersPage from "./LettersPage.jsx";
import DateBoard from "./DateBoard.jsx";

// service worker only handles notifications, not local photo caching.
if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(() => {});

function App() {
  const [view, setView] = useState("map");
  return view === "dates"
    ? <DateBoard onBack={() => setView("map")} />
    : <LettersPage onShowDates={() => setView("dates")} />;
}

createRoot(document.getElementById("root")).render(<App />);
