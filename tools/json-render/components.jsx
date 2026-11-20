import React from 'react';
import {defineRegistry} from '@json-render/react';
import {shadcnComponents} from '@json-render/shadcn';
import {catalog} from './catalog.mjs';
const Metric=({props})=><section className="metric"><p>{props.label}</p><strong>{props.value}</strong>{props.detail&&<p>{props.detail}</p>}</section>;
const BarChart=({props})=>{
  const values=props.items.map(item=>item.value);
  const magnitude=Math.max(...values.map(Math.abs), Number.MIN_VALUE);
  const hasNegative=values.some(value=>value<0);
  const hasPositive=values.some(value=>value>0);
  const zero=hasNegative ? (hasPositive ? 50 : 100) : 0;
  const span=hasNegative && hasPositive ? 50 : 100;
  const formatter=new Intl.NumberFormat('ja-JP',{maximumSignificantDigits:21});
  return <section>
    <h3>{props.title}</h3>
    <dl>{props.items.map((item,index)=>{
      const width=Math.abs(item.value)/magnitude*span;
      return <div key={index} className="chart-row">
        <dt>{item.label}</dt>
        <dd>
          <div aria-hidden="true" className="chart-track" style={{'--zero':zero+'%'}}>
            <div className="chart-bar" style={{insetInlineStart:(item.value<0 ? zero-width : zero)+'%',width:width+'%'}}/>
          </div>
          <span>{formatter.format(item.value)}{props.unit ? ' '+props.unit : ''}</span>
        </dd>
      </div>;
    })}</dl>
  </section>;
};
const Panel=({props,children,slots})=><section aria-label={props.label??undefined} className="panel">{slots?.header&&<header>{slots.header}</header>}{children}{slots?.footer&&<footer>{slots.footer}</footer>}</section>;
export const {registry}=defineRegistry(catalog,{components:{...shadcnComponents,Metric,BarChart,Panel}});

