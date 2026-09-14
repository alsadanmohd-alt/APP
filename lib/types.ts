export type Point={lat:number;lng:number};
export type Item={id:string;owner_id:string;title:string;description:string;category:string;daily_price:number;contact_phone:string;area:string;lat:number;lng:number;images:string[];created_at?:string};
export type Booking={id:string;item_id:string;renter_id:string;owner_id:string;created_at:string};
export type Review={id:string;booking_id:string;item_id:string;author_id:string;rating:number;body:string};
export type Message={id:string;booking_id:string;sender_id:string;body:string;created_at:string};
export const categories=['الكل','تصوير','رحلات','أدوات ومعدات','رياضة','منزل','إلكترونيات','تجهيز الحفلات','أدوات مطبخ','أخرى'];
