import Marketplace from '@/components/Marketplace';
export default async function UserPage({params}:{params:Promise<{id:string}>}){const {id}=await params;return <Marketplace initialProfileId={id}/>}
