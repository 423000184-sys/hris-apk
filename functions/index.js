const { onDocumentDeleted } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore();

const LINKED_COLLECTIONS = [
  "activity_logs",
  "attendance_logs",
  "clock_ins",
  "clock_outs",
  "leave_applications",
  "user_locations",
];

exports.cascadeDeleteEmployeeData = onDocumentDeleted(
  "employees/{employeeId}",
  async (event) => {
    const employeeId = event.params.employeeId;

    for (const collectionName of LINKED_COLLECTIONS) {
      const snapshot = await db
        .collection(collectionName)
        .where("employeeId", "==", employeeId)
        .get();

      if (snapshot.empty) continue;

      const batch = db.batch();
      snapshot.docs.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();

      console.log(
        `Deleted ${snapshot.size} doc(s) from ${collectionName} for employee ${employeeId}`
      );
    }
  }
);