export type Point={lat:number;lng:number};
export type Item={id:string;owner_id:string;title:string;description:string;category:string;daily_price:number;deposit_amount:number;area:string;lat:number;lng:number;images:string[];created_at?:string};
export type Booking={id:string;item_id:string;renter_id:string;owner_id:string;starts_on:string;ends_on:string;total:number;deposit_amount:number;status:'pending'|'accepted'|'rejected'|'cancelled'|'completed';created_at:string};
export type Review={id:string;booking_id:string;item_id:string;author_id:string;rating:number;body:string};
export type Message={id:string;booking_id:string;sender_id:string;body:string;created_at:string};
export const categories=['الكل','تصوير','رحلات','أدوات ومعدات','رياضة','منزل','إلكترونيات','تجهيز الحفلات'];
export const statuses={pending:'بانتظار الموافقة',accepted:'مؤكد',rejected:'مرفوض',cancelled:'ملغي',completed:'مكتمل'};
