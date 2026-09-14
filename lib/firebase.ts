import {initializeApp,getApps,type FirebaseApp} from 'firebase/app';
import {isSupported,getAnalytics,type Analytics} from 'firebase/analytics';
const firebaseConfig={
 apiKey:process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
 authDomain:process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
 projectId:process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
 storageBucket:process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET,
 messagingSenderId:process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID,
 appId:process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
 measurementId:process.env.NEXT_PUBLIC_FIREBASE_MEASUREMENT_ID,
};
export const firebaseApp:FirebaseApp|null=firebaseConfig.apiKey&&firebaseConfig.projectId&&firebaseConfig.appId
 ?(getApps()[0]??initializeApp(firebaseConfig))
 :null;
let analytics:Analytics|null=null;
// Analytics needs a browser (uses cookies/IndexedDB) and isn't supported in every environment
// (e.g. some browsers with tracking protection), so this must run client-side and be checked first.
export async function getFirebaseAnalytics():Promise<Analytics|null>{
 if(analytics)return analytics;
 if(!firebaseApp||typeof window==='undefined')return null;
 if(!(await isSupported()))return null;
 analytics=getAnalytics(firebaseApp);
 return analytics;
}
