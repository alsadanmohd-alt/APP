import type { Metadata } from 'next';
import './globals.css';
import FirebaseAnalytics from '@/components/FirebaseAnalytics';
export const metadata: Metadata = {title:'قريب | استأجر ما تحتاجه من حولك',description:'تأجير الأغراض بين الأشخاص بالقرب منك',manifest:'/manifest.webmanifest',icons:{icon:'/icon.svg',apple:'/icon.svg'},appleWebApp:{capable:true,title:'قريب',statusBarStyle:'default'}};
export default function Layout({children}:{children:React.ReactNode}) {return <html lang="ar" dir="rtl"><body>{children}<FirebaseAnalytics/></body></html>}
