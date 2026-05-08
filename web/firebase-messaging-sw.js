importScripts("https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js");

// Gebruik hier dezelfde config als in main.dart
const firebaseConfig = {
  apiKey: "AIzaSyA2moE0PBhjK2CNAswryCIYT4IFmBrs2Rs",
  appId: "1:893774085991:web:c54c505f5bc2f4d05c39c2",
  messagingSenderId: "893774085991",
  projectId: "cleanconnect-erp",
};

firebase.initializeApp(firebaseConfig);
const messaging = firebase.messaging();

// Optioneel: Achtergrond meldingen afvangen
messaging.onBackgroundMessage((payload) => {
  console.log("Ontvangen achtergrond melding: ", payload);
  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: "/icons/Icon-192.png", // Pas aan naar jullie PWA icoon
  };
  return self.registration.showNotification(notificationTitle, notificationOptions);
});

