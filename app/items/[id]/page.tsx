import Marketplace from '@/components/Marketplace';
export default async function ItemPage({params}:{params:Promise<{id:string}>}){const {id}=await params;return <Marketplace initialItemId={id}/>}
