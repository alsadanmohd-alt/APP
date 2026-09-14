'use client';
import {useState,useEffect,useCallback} from 'react';
import {Trash2} from 'lucide-react';
import {db} from '@/lib/supabase';
import type {Item,AdminUser} from '@/lib/types';

export default function AdminPage(){
 const [status,setStatus]=useState<'checking'|'denied'|'ok'>('checking');
 const [tab,setTab]=useState<'items'|'users'>('items');
 const [items,setItems]=useState<Item[]>([]);
 const [users,setUsers]=useState<AdminUser[]>([]);
 const [notice,setNotice]=useState('');
 const [busy,setBusy]=useState(false);

 const loadItems=useCallback(async()=>{if(!db)return;const {data,error}=await db.from('items').select('*').order('created_at',{ascending:false});if(!error)setItems(data||[])},[]);
 const loadUsers=useCallback(async()=>{if(!db)return;const {data,error}=await db.rpc('admin_list_users');if(!error)setUsers(data||[])},[]);

 useEffect(()=>{
  if(!db){setStatus('denied');return}
  (async()=>{
   const {data:{user}}=await db!.auth.getUser();
   if(!user){setStatus('denied');return}
   const {data}=await db!.from('admins').select('id').eq('id',user.id).maybeSingle();
   if(!data){setStatus('denied');return}
   setStatus('ok');
   await Promise.all([loadItems(),loadUsers()]);
  })();
 },[loadItems,loadUsers]);

 const deleteItem=(id:string,title:string)=>{
  if(!window.confirm(`حذف "${title}"؟ هذا الإجراء نهائي ولا يمكن التراجع عنه.`))return;
  setBusy(true);
  db!.from('items').delete().eq('id',id).then(({error})=>{
   setBusy(false);
   if(error){setNotice(error.message);return}
   setItems(prev=>prev.filter(i=>i.id!==id));
   setNotice('تم حذف الغرض');
  });
 };

 if(status==='checking')return <div className="admin-page"><p>جارٍ التحقق من الصلاحية…</p></div>;
 if(status==='denied')return <div className="admin-page"><p>غير مصرح لك بالوصول لهذه الصفحة.</p></div>;

 const newest=[...items].slice(0,10);

 return <div className="admin-page">
  <h1>لوحة الإدارة</h1>
  <p className="admin-scope-note">تقتصر هذه اللوحة على الإعلانات والمستخدمين. المحادثات الخاصة بين المستخدمين تبقى غير متاحة حتى لهذا الحساب.</p>
  {notice&&<p className="dialog-notice" role="alert">{notice}</p>}
  <div className="dashboard-tabs">
   <button className={tab==='items'?'active':''} onClick={()=>setTab('items')}>الإعلانات ({items.length})</button>
   <button className={tab==='users'?'active':''} onClick={()=>setTab('users')}>المستخدمون ({users.length})</button>
  </div>
  {tab==='items'&&<section>
   <h2>أحدث الإعلانات</h2>
   <ul className="admin-list">{newest.map(i=><li key={i.id}><span>{i.title}</span><small>{i.created_at?new Date(i.created_at).toLocaleString('ar-SA'):''}</small></li>)}{!newest.length&&<li>لا توجد إعلانات بعد.</li>}</ul>
   <h2>جميع الإعلانات</h2>
   <div className="admin-table-wrap"><table className="admin-table"><thead><tr><th>الاسم</th><th>الفئة</th><th>السعر</th><th>المنطقة</th><th>تاريخ الإضافة</th><th></th></tr></thead>
    <tbody>{items.map(i=><tr key={i.id}><td>{i.title}</td><td>{i.category}</td><td>{i.daily_price} ر.س</td><td>{i.area}</td><td>{i.created_at?new Date(i.created_at).toLocaleDateString('ar-SA'):''}</td><td><button disabled={busy} className="icon-button" aria-label="حذف الغرض" onClick={()=>deleteItem(i.id,i.title)}><Trash2 size={16}/></button></td></tr>)}</tbody>
   </table></div>
  </section>}
  {tab==='users'&&<section><div className="admin-table-wrap"><table className="admin-table"><thead><tr><th>الاسم المستعار</th><th>الجوال</th><th>تاريخ التسجيل</th></tr></thead>
   <tbody>{users.map(u=><tr key={u.id}><td>{u.display_name}</td><td dir="ltr">{u.phone}</td><td>{new Date(u.created_at).toLocaleDateString('ar-SA')}</td></tr>)}</tbody>
  </table></div></section>}
 </div>;
}
