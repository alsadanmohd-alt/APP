'use client';
import { useEffect,useRef } from 'react';
import type {Item,Point} from '@/lib/types';
export default function Map({items,center,onSelect}:{items:Item[];center:Point;onSelect:(item:Item)=>void}){
 const el=useRef<HTMLDivElement>(null);
 useEffect(()=>{let disposed=false;let map:import('leaflet').Map|undefined;
 import('leaflet').then(L=>{if(disposed||!el.current)return;map=L.map(el.current).setView([center.lat,center.lng],12);
 L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{attribution:'&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',maxZoom:18}).addTo(map);
 for(const item of items){L.circle([item.lat,item.lng],{radius:650,color:'#087f68',weight:1,fillOpacity:.08}).addTo(map);const marker=L.marker([item.lat,item.lng],{icon:L.divIcon({className:'price-pin',html:`<span>${Number(item.daily_price)} ر.س</span>`,iconSize:[80,34],iconAnchor:[40,17]})}).addTo(map);marker.on('click',()=>onSelect(item));const label=document.createElement('span');label.textContent=item.title;marker.bindTooltip(label);}
 });return()=>{disposed=true;map?.remove()};},[items,center,onSelect]);
 return <div className="map" ref={el} role="region" aria-label="خريطة المواقع التقريبية للأغراض"/>;
}
